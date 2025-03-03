# We need a version of the integration function that runs a single timestep and 
# takes as input the current prognostic fields. This function will then be
# passed to Enzyme for computing the Jacobian, which can subsequently be used
# in the Kalman filter. We're giving as input uveta, which will be a block
# vector of the fields u, v, and eta in that order. The restructuring of the
# arrays will be as columns stacked on top of eachother, e.g. the first column becomes
# the first bit of the vector, the second column the second bit, and so on.

using Parameters
# Enzyme.API.looseTypeAnalysis!(true)

"""
This function will run the ensemble Kalman filter. It needs to be given:
    N - the number of ensembles to build
    Ndays - the number of days to integrate
    data - the data to be used
    data_steps - where we assume data exists
    data_spots - the spatial locations within Z (dim(Z) = state_vector x number of ensembles)
      where we assume data to exist. This could be all of u, it could be specific locations in u
    sigma_initcond - std of noise added to initial condition for each of the ensembles
    sigma_data - std of the noise added to data
"""
function run_ensemble_kf(N, data, param_guess, data_spots, sigma_initcond, sigma_data;
    kwargs...
    )

    uic = reshape(param_guess[1:17292], 131, 132)
    vic = reshape(param_guess[17293:34584], 132, 131)
    etaic = reshape(param_guess[34585:end], 130, 130)

    Π = (I - (1 / N)*(ones(N) * ones(N)')) / sqrt(N - 1)
    W = zeros(N,N)
    T = zeros(N,N)

    P = ShallowWaters.Parameter(T=Float32;kwargs...)
    S_for_values = ShallowWaters.model_setup(P)

    S = zeros(length(data[:,1]), N)
    U = zeros(length(data[:,1]), N)

    # Generate the initial model realization ensemble,
    # generated by slightly perturbing the initial condition N times.
    # Output will be stored in the matrix Z, and all model structs will be
    # stored in S_all
    # We assume that Z is the total state vector in size, so 48896 is the
    # whole length of u + v + eta as a column vector
    Z = zeros(48896, N)
    S_all = []
    Progkf_all = []
    for n = 1:N

        # P_kf = ShallowWaters.Parameter(T=Float32;kwargs...)
        S_kf = ShallowWaters.model_setup(P)

        S_kf.Prog.u = uic
        S_kf.Prog.v = vic
        S_kf.Prog.η = etaic

        P_kf = ShallowWaters.PrognosticVars{Float32}(ShallowWaters.remove_halo(S_kf.Prog.u,
            S_kf.Prog.v,
            S_kf.Prog.η,
            S_kf.Prog.sst,
            S_kf)...
        )

        # perturb initial conditions from the guessed value for each ensemble member
        P_kf.u = P_kf.u + sigma_initcond .* randn(size(P_kf.u))
        P_kf.v = P_kf.v + sigma_initcond .* randn(size(P_kf.v))
        P_kf.η = P_kf.η + sigma_initcond .* randn(size(P_kf.η))

        Z[:, n] = [vec(P_kf.u); vec(P_kf.v); vec(P_kf.η)]

        uic,vic,etaic = ShallowWaters.add_halo(P_kf.u,P_kf.v,P_kf.η,P_kf.sst,S_kf)

        S_kf.Prog.u = uic
        S_kf.Prog.v = vic
        S_kf.Prog.η = etaic

        Diag = S_kf.Diag
        Prog = S_kf.Prog
    
        @unpack u,v,η,sst = Prog
        @unpack u0,v0,η0 = Diag.RungeKutta
        @unpack u1,v1,η1 = Diag.RungeKutta
        @unpack du,dv,dη = Diag.Tendencies
        @unpack du_sum,dv_sum,dη_sum = Diag.Tendencies
        @unpack du_comp,dv_comp,dη_comp = Diag.Tendencies
    
        @unpack um,vm = Diag.SemiLagrange
    
        @unpack dynamics,RKo,RKs,tracer_advection = S_kf.parameters
        @unpack time_scheme,compensated = S_kf.parameters
        @unpack RKaΔt,RKbΔt = S_kf.constants
        @unpack Δt_Δ,Δt_Δs = S_kf.constants
    
        @unpack nt,dtint = S_kf.grid
        @unpack nstep_advcor,nstep_diff,nadvstep,nadvstep_half = S_kf.grid
    
        # calculate layer thicknesses for initial conditions
        ShallowWaters.thickness!(Diag.VolumeFluxes.h,η,S_kf.forcing.H)
        ShallowWaters.Ix!(Diag.VolumeFluxes.h_u,Diag.VolumeFluxes.h)
        ShallowWaters.Iy!(Diag.VolumeFluxes.h_v,Diag.VolumeFluxes.h)
        ShallowWaters.Ixy!(Diag.Vorticity.h_q,Diag.VolumeFluxes.h)
    
        # calculate PV terms for initial conditions
        urhs = convert(Diag.PrognosticVarsRHS.u,u)
        vrhs = convert(Diag.PrognosticVarsRHS.v,v)
        ηrhs = convert(Diag.PrognosticVarsRHS.η,η)
    
        ShallowWaters.advection_coriolis!(urhs,vrhs,ηrhs,Diag,S_kf)
        ShallowWaters.PVadvection!(Diag,S_kf)
    
        # propagate initial conditions
        copyto!(u0,u)
        copyto!(v0,v)
        copyto!(η0,η)
    
        # store initial conditions of sst for relaxation
        copyto!(Diag.SemiLagrange.sst_ref,sst)

        push!(S_all, S_kf)

    end

    for t = 1:S_for_values.grid.nt

        Progkf = []

        for n = 1:N

            p = one_step_function(S_all[n])
            push!(Progkf, p)

        end

        if t ∈ 1:225:S_for_values.grid.nt
            push!(Progkf_all, Progkf)
        end

        if t ∈ S_for_values.parameters.data_steps

            d = data[:, S_for_values.parameters.j]
            E = sigma_data .* randn(size(data[:,1])[1], N)
            D = d * ones(N)' + sqrt(N - 1) * E
            E = D * Π

            for k = 1:N

                Z[:, k] = [vec(Progkf[k].u); vec(Progkf[k].v); vec(Progkf[k].η)]
                U[:, k] = Z[Int.(data_spots), k]

            end

            Y = U * Π

            S .= Y
            D̃ = D - U
            W = S' * (S*S' + E*E')^(-1)*D̃

            T = (I + W./(sqrt(N-1)))

            Z = Z*T

            for k = 1:N

                u,v,eta = ShallowWaters.add_halo(Progkf[k].u,
                    Progkf[k].v,
                    Progkf[k].η,
                    Progkf[k].sst,
                    S_all[k]
                )

                S_all[k].Prog.u = u
                S_all[k].Prog.v = v 
                S_all[k].Prog.η = eta

            end

            S_for_values.parameters.j += 1

        end

    end

    return S_all, Progkf_all

end

function exp3_run_ensemble_kf(N, data, param_guess, data_spots, sigma_initcond, sigma_data;
    kwargs...
    )

    uic = reshape(param_guess[1:17292], 131, 132)
    vic = reshape(param_guess[17293:34584], 132, 131)
    etaic = reshape(param_guess[34585:end-1], 130, 130)

    Π = (I - (1 / N)*(ones(N) * ones(N)')) / sqrt(N - 1)
    W = zeros(N,N)
    T = zeros(N,N)

    P = ShallowWaters.Parameter(T=Float32;kwargs...)
    S_for_values = ShallowWaters.model_setup(P)

    S = zeros(length(data[:,1]), N)
    U = zeros(length(data[:,1]), N)

    # Generate the initial model realization ensemble,
    # generated by slightly perturbing the initial condition N times.
    # Output will be stored in the matrix Z, and all model structs will be
    # stored in S_all
    # We assume that Z is the total state vector in size, so 48896 is the
    # whole length of u + v + eta as a column vector
    Z = zeros(48896, N)
    S_all = []
    Progkf_all = []
    for n = 1:N

        # P_kf = ShallowWaters.Parameter(T=Float32;kwargs...)
        S_kf = ShallowWaters.model_setup(P)

        S_kf.Prog.u = uic
        S_kf.Prog.v = vic
        S_kf.Prog.η = etaic
        S_kf.parameters.Fx0 = param_guess[end]

        P_kf = ShallowWaters.PrognosticVars{Float32}(ShallowWaters.remove_halo(S_kf.Prog.u,
            S_kf.Prog.v,
            S_kf.Prog.η,
            S_kf.Prog.sst,
            S_kf)...
        )

        # perturb initial conditions from the guessed value for each ensemble member
        P_kf.u = P_kf.u + sigma_initcond .* randn(size(P_kf.u))
        P_kf.v = P_kf.v + sigma_initcond .* randn(size(P_kf.v))
        P_kf.η = P_kf.η + sigma_initcond .* randn(size(P_kf.η))

        Z[:, n] = [vec(P_kf.u); vec(P_kf.v); vec(P_kf.η)]

        uic,vic,etaic = ShallowWaters.add_halo(P_kf.u,P_kf.v,P_kf.η,P_kf.sst,S_kf)

        S_kf.Prog.u = uic
        S_kf.Prog.v = vic
        S_kf.Prog.η = etaic

        Diag = S_kf.Diag
        Prog = S_kf.Prog
    
        @unpack u,v,η,sst = Prog
        @unpack u0,v0,η0 = Diag.RungeKutta
        @unpack u1,v1,η1 = Diag.RungeKutta
        @unpack du,dv,dη = Diag.Tendencies
        @unpack du_sum,dv_sum,dη_sum = Diag.Tendencies
        @unpack du_comp,dv_comp,dη_comp = Diag.Tendencies
    
        @unpack um,vm = Diag.SemiLagrange
    
        @unpack dynamics,RKo,RKs,tracer_advection = S_kf.parameters
        @unpack time_scheme,compensated = S_kf.parameters
        @unpack RKaΔt,RKbΔt = S_kf.constants
        @unpack Δt_Δ,Δt_Δs = S_kf.constants
    
        @unpack nt,dtint = S_kf.grid
        @unpack nstep_advcor,nstep_diff,nadvstep,nadvstep_half = S_kf.grid
    
        # calculate layer thicknesses for initial conditions
        ShallowWaters.thickness!(Diag.VolumeFluxes.h,η,S_kf.forcing.H)
        ShallowWaters.Ix!(Diag.VolumeFluxes.h_u,Diag.VolumeFluxes.h)
        ShallowWaters.Iy!(Diag.VolumeFluxes.h_v,Diag.VolumeFluxes.h)
        ShallowWaters.Ixy!(Diag.Vorticity.h_q,Diag.VolumeFluxes.h)
    
        # calculate PV terms for initial conditions
        urhs = convert(Diag.PrognosticVarsRHS.u,u)
        vrhs = convert(Diag.PrognosticVarsRHS.v,v)
        ηrhs = convert(Diag.PrognosticVarsRHS.η,η)
    
        ShallowWaters.advection_coriolis!(urhs,vrhs,ηrhs,Diag,S_kf)
        ShallowWaters.PVadvection!(Diag,S_kf)
    
        # propagate initial conditions
        copyto!(u0,u)
        copyto!(v0,v)
        copyto!(η0,η)
    
        # store initial conditions of sst for relaxation
        copyto!(Diag.SemiLagrange.sst_ref,sst)

        push!(S_all, S_kf)

    end

    for t = 1:S_for_values.grid.nt

        Progkf = []

        for n = 1:N

            p = one_step_function(S_all[n])
            push!(Progkf, p)

        end

        if t ∈ 1:225:S_for_values.grid.nt
            push!(Progkf_all, Progkf)
        end

        if t ∈ S_for_values.parameters.data_steps

            d = data[:, S_for_values.parameters.j]
            E = sigma_data .* randn(size(data[:,1])[1], N)
            D = d * ones(N)' + sqrt(N - 1) * E
            E = D * Π

            for k = 1:N

                Z[:, k] = [vec(Progkf[k].u); vec(Progkf[k].v); vec(Progkf[k].η)]
                U[:, k] = Z[Int.(data_spots), k]

            end

            Y = U * Π

            S .= Y
            D̃ = D - U
            W = S' * (S*S' + E*E')^(-1)*D̃

            T = (I + W./(sqrt(N-1)))

            Z = Z*T

            for k = 1:N

                u,v,eta = ShallowWaters.add_halo(Progkf[k].u,
                    Progkf[k].v,
                    Progkf[k].η,
                    Progkf[k].sst,
                    S_all[k]
                )

                S_all[k].Prog.u = u
                S_all[k].Prog.v = v 
                S_all[k].Prog.η = eta

            end

            S_for_values.parameters.j += 1

        end

    end

    return S_all, Progkf_all

end