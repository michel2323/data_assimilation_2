function u_mat_to_vec(u_mat)

    m, n = size(u_mat)
    u_vec = reshape(u_mat, (m*n))

    return u_vec

end

function v_mat_to_vec(v_mat)

    m, n = size(v_mat)
    v_vec = reshape(v_mat, (m*n))

    return v_vec

end

function eta_mat_to_vec(eta_mat)

    m, n = size(eta_mat)
    eta_vec = reshape(eta_mat, (m*n))

    return eta_vec

end

function u_vec_to_mat(u_vec,S)
    nx = S.grid.nx
    u_mat = reshape(u_vec, nx-1, nx)
    return u_mat
end

function v_vec_to_mat(v_vec,S)
    nx = S.grid.nx
    v_mat = reshape(v_vec, nx, nx-1)
    return v_mat
end

function eta_vec_to_mat(eta_vec,S)
    nx = S.grid.nx
    eta_mat = reshape(eta_vec,nx,nx)
    return eta_mat
end

# function one_step_function(S)

#     Diag = S.Diag
#     Prog = S.Prog

#     @unpack u,v,η,sst = Prog
#     @unpack u0,v0,η0 = Diag.RungeKutta
#     @unpack u1,v1,η1 = Diag.RungeKutta
#     @unpack du,dv,dη = Diag.Tendencies
#     @unpack du_sum,dv_sum,dη_sum = Diag.Tendencies
#     @unpack du_comp,dv_comp,dη_comp = Diag.Tendencies

#     @unpack um,vm = Diag.SemiLagrange

#     @unpack dynamics,RKo,RKs,tracer_advection = S.parameters
#     @unpack time_scheme,compensated = S.parameters
#     @unpack RKaΔt,RKbΔt = S.constants
#     @unpack Δt_Δ,Δt_Δs = S.constants

#     @unpack nt,dtint = S.grid
#     @unpack nstep_advcor,nstep_diff,nadvstep,nadvstep_half = S.grid
#     t = S.t
#     i = S.parameters.i

#     # ghost point copy for boundary conditions
#     ShallowWaters.ghost_points!(u,v,η,S)
#     copyto!(u1,u)
#     copyto!(v1,v)
#     copyto!(η1,η)


#     if compensated
#         fill!(du_sum,zero(Tprog))
#         fill!(dv_sum,zero(Tprog))
#         fill!(dη_sum,zero(Tprog))
#     end

#     for rki = 1:RKo
#         if rki > 1
#             ShallowWaters.ghost_points!(u1,v1,η1,S)
#         end

#         # type conversion for mixed precision
#         u1rhs = convert(Diag.PrognosticVarsRHS.u,u1)
#         v1rhs = convert(Diag.PrognosticVarsRHS.v,v1)
#         η1rhs = convert(Diag.PrognosticVarsRHS.η,η1)

#         ShallowWaters.rhs!(u1rhs,v1rhs,η1rhs,Diag,S,t)          # momentum only
#         ShallowWaters.continuity!(u1rhs,v1rhs,η1rhs,Diag,S,t)   # continuity equation

#         if rki < RKo
#             ShallowWaters.caxb!(u1,u,RKbΔt[rki],du)   #u1 .= u .+ RKb[rki]*Δt*du
#             ShallowWaters.caxb!(v1,v,RKbΔt[rki],dv)   #v1 .= v .+ RKb[rki]*Δt*dv
#             ShallowWaters.caxb!(η1,η,RKbΔt[rki],dη)   #η1 .= η .+ RKb[rki]*Δt*dη
#         end

#         if compensated      # accumulate tendencies
#             ShallowWaters.axb!(du_sum,RKaΔt[rki],du)
#             ShallowWaters.axb!(dv_sum,RKaΔt[rki],dv)
#             ShallowWaters.axb!(dη_sum,RKaΔt[rki],dη)
#         else    # sum RK-substeps on the go
#             ShallowWaters.axb!(u0,RKaΔt[rki],du)          #u0 .+= RKa[rki]*Δt*du
#             ShallowWaters.axb!(v0,RKaΔt[rki],dv)          #v0 .+= RKa[rki]*Δt*dv
#             ShallowWaters.axb!(η0,RKaΔt[rki],dη)          #η0 .+= RKa[rki]*Δt*dη
#         end
#     end

#     if compensated
#         # add compensation term to total tendency
#         ShallowWaters.axb!(du_sum,-1,du_comp)
#         ShallowWaters.axb!(dv_sum,-1,dv_comp)
#         ShallowWaters.axb!(dη_sum,-1,dη_comp)

#         ShallowWaters.axb!(u0,1,du_sum)   # update prognostic variable with total tendency
#         ShallowWaters.axb!(v0,1,dv_sum)
#         ShallowWaters.axb!(η0,1,dη_sum)

#         ShallowWaters.dambmc!(du_comp,u0,u,du_sum)    # compute new compensation
#         ShallowWaters.dambmc!(dv_comp,v0,v,dv_sum)
#         ShallowWaters.dambmc!(dη_comp,η0,η,dη_sum)
#     end

#     ShallowWaters.ghost_points!(u0,v0,η0,S)

#     # type conversion for mixed precision
#     u0rhs = convert(Diag.PrognosticVarsRHS.u,u0)
#     v0rhs = convert(Diag.PrognosticVarsRHS.v,v0)
#     η0rhs = convert(Diag.PrognosticVarsRHS.η,η0)

#     # ADVECTION and CORIOLIS TERMS
#     # although included in the tendency of every RK substep,
#     # only update every nstep_advcor steps if nstep_advcor > 0
#     if dynamics == "nonlinear" && nstep_advcor > 0 && (i % nstep_advcor) == 0
#         ShallowWaters.UVfluxes!(u0rhs,v0rhs,η0rhs,Diag,S)
#         ShallowWaters.advection_coriolis!(u0rhs,v0rhs,η0rhs,Diag,S)
#     end

#     # DIFFUSIVE TERMS - SEMI-IMPLICIT EULER
#     # use u0 = u^(n+1) to evaluate tendencies, add to u0 = u^n + rhs
#     # evaluate only every nstep_diff time steps
#     if (S.parameters.i % nstep_diff) == 0
#         ShallowWaters.bottom_drag!(u0rhs,v0rhs,η0rhs,Diag,S)
#         ShallowWaters.diffusion!(u0rhs,v0rhs,Diag,S)
#         ShallowWaters.add_drag_diff_tendencies!(u0,v0,Diag,S)
#         ShallowWaters.ghost_points_uv!(u0,v0,S)
#     end

#     t += dtint

#     # TRACER ADVECTION
#     u0rhs = convert(Diag.PrognosticVarsRHS.u,u0) 
#     v0rhs = convert(Diag.PrognosticVarsRHS.v,v0)
#     ShallowWaters.tracer!(i,u0rhs,v0rhs,Prog,Diag,S)

#     # Copy back from substeps
#     copyto!(u,u0)
#     copyto!(v,v0)
#     copyto!(η,η0)

#     return ShallowWaters.PrognosticVars{S.parameters.Tprog}(ShallowWaters.remove_halo(u,v,η,sst,S)...)

# end

function generate_data(data_spots, sigma_data; kwargs...)

    # Create the "true" model, from this we'll make data
    P = ShallowWaters.Parameter(T=Float32; kwargs...)
    S_true = ShallowWaters.model_setup(P)

    data = Float32.(zeros(length(data_spots), length(S_true.parameters.data_steps)))
    true_states = []

    # setup
    Diag = S_true.Diag
    Prog = S_true.Prog

    @unpack u,v,η,sst = Prog
    @unpack u0,v0,η0 = Diag.RungeKutta
    @unpack u1,v1,η1 = Diag.RungeKutta
    @unpack du,dv,dη = Diag.Tendencies
    @unpack du_sum,dv_sum,dη_sum = Diag.Tendencies
    @unpack du_comp,dv_comp,dη_comp = Diag.Tendencies

    @unpack um,vm = Diag.SemiLagrange

    @unpack dynamics,RKo,RKs,tracer_advection = S_true.parameters
    @unpack time_scheme,compensated = S_true.parameters
    @unpack RKaΔt,RKbΔt = S_true.constants
    @unpack Δt_Δ,Δt_Δs = S_true.constants

    @unpack nt,dtint = S_true.grid
    @unpack nstep_advcor,nstep_diff,nadvstep,nadvstep_half = S_true.grid

    # calculate layer thicknesses for initial conditions
    ShallowWaters.thickness!(Diag.VolumeFluxes.h,η,S_true.forcing.H)
    ShallowWaters.Ix!(Diag.VolumeFluxes.h_u,Diag.VolumeFluxes.h)
    ShallowWaters.Iy!(Diag.VolumeFluxes.h_v,Diag.VolumeFluxes.h)
    ShallowWaters.Ixy!(Diag.Vorticity.h_q,Diag.VolumeFluxes.h)

    # calculate PV terms for initial conditions
    urhs = convert(Diag.PrognosticVarsRHS.u,u)
    vrhs = convert(Diag.PrognosticVarsRHS.v,v)
    ηrhs = convert(Diag.PrognosticVarsRHS.η,η)

    ShallowWaters.advection_coriolis!(urhs,vrhs,ηrhs,Diag,S_true)
    ShallowWaters.PVadvection!(Diag,S_true)

    # propagate initial conditions
    copyto!(u0,u)
    copyto!(v0,v)
    copyto!(η0,η)

    # store initial conditions of sst for relaxation
    copyto!(Diag.SemiLagrange.sst_ref,sst)
    j = 1

    for t = 1:S_true.grid.nt

        Diag = S_true.Diag
        Prog = S_true.Prog
    
        @unpack u,v,η,sst = Prog
        @unpack u0,v0,η0 = Diag.RungeKutta
        @unpack u1,v1,η1 = Diag.RungeKutta
        @unpack du,dv,dη = Diag.Tendencies
        @unpack du_sum,dv_sum,dη_sum = Diag.Tendencies
        @unpack du_comp,dv_comp,dη_comp = Diag.Tendencies
    
        @unpack um,vm = Diag.SemiLagrange
    
        @unpack dynamics,RKo,RKs,tracer_advection = S_true.parameters
        @unpack time_scheme,compensated = S_true.parameters
        @unpack RKaΔt,RKbΔt = S_true.constants
        @unpack Δt_Δ,Δt_Δs = S_true.constants
    
        @unpack nt,dtint = S_true.grid
        @unpack nstep_advcor,nstep_diff,nadvstep,nadvstep_half = S_true.grid
        i = S_true.parameters.i

        # ghost point copy for boundary conditions
        ShallowWaters.ghost_points!(u,v,η,S_true)
        copyto!(u1,u)
        copyto!(v1,v)
        copyto!(η1,η)

        if compensated
            fill!(du_sum,zero(Tprog))
            fill!(dv_sum,zero(Tprog))
            fill!(dη_sum,zero(Tprog))
        end

        for rki = 1:RKo
            if rki > 1
                ShallowWaters.ghost_points!(u1,v1,η1,S_true)
            end

            # type conversion for mixed precision
            u1rhs = convert(Diag.PrognosticVarsRHS.u,u1)
            v1rhs = convert(Diag.PrognosticVarsRHS.v,v1)
            η1rhs = convert(Diag.PrognosticVarsRHS.η,η1)

            ShallowWaters.rhs!(u1rhs,v1rhs,η1rhs,Diag,S_true,t)          # momentum only
            ShallowWaters.continuity!(u1rhs,v1rhs,η1rhs,Diag,S_true,t)   # continuity equation

            if rki < RKo
                ShallowWaters.caxb!(u1,u,RKbΔt[rki],du)   #u1 .= u .+ RKb[rki]*Δt*du
                ShallowWaters.caxb!(v1,v,RKbΔt[rki],dv)   #v1 .= v .+ RKb[rki]*Δt*dv
                ShallowWaters.caxb!(η1,η,RKbΔt[rki],dη)   #η1 .= η .+ RKb[rki]*Δt*dη
            end

            if compensated      # accumulate tendencies
                ShallowWaters.axb!(du_sum,RKaΔt[rki],du)
                ShallowWaters.axb!(dv_sum,RKaΔt[rki],dv)
                ShallowWaters.axb!(dη_sum,RKaΔt[rki],dη)
            else    # sum RK-substeps on the go
                ShallowWaters.axb!(u0,RKaΔt[rki],du)          #u0 .+= RKa[rki]*Δt*du
                ShallowWaters.axb!(v0,RKaΔt[rki],dv)          #v0 .+= RKa[rki]*Δt*dv
                ShallowWaters.axb!(η0,RKaΔt[rki],dη)          #η0 .+= RKa[rki]*Δt*dη
            end
        end

        if compensated
            # add compensation term to total tendency
            ShallowWaters.axb!(du_sum,-1,du_comp)
            ShallowWaters.axb!(dv_sum,-1,dv_comp)
            ShallowWaters.axb!(dη_sum,-1,dη_comp)

            ShallowWaters.axb!(u0,1,du_sum)   # update prognostic variable with total tendency
            ShallowWaters.axb!(v0,1,dv_sum)
            ShallowWaters.axb!(η0,1,dη_sum)

            ShallowWaters.dambmc!(du_comp,u0,u,du_sum)    # compute new compensation
            ShallowWaters.dambmc!(dv_comp,v0,v,dv_sum)
            ShallowWaters.dambmc!(dη_comp,η0,η,dη_sum)
        end

        ShallowWaters.ghost_points!(u0,v0,η0,S_true)

        # type conversion for mixed precision
        u0rhs = convert(Diag.PrognosticVarsRHS.u,u0)
        v0rhs = convert(Diag.PrognosticVarsRHS.v,v0)
        η0rhs = convert(Diag.PrognosticVarsRHS.η,η0)

        # ADVECTION and CORIOLIS TERMS
        # although included in the tendency of every RK substep,
        # only update every nstep_advcor steps if nstep_advcor > 0
        if dynamics == "nonlinear" && nstep_advcor > 0 && (i % nstep_advcor) == 0
            ShallowWaters.UVfluxes!(u0rhs,v0rhs,η0rhs,Diag,S_true)
            ShallowWaters.advection_coriolis!(u0rhs,v0rhs,η0rhs,Diag,S_true)
        end

        # DIFFUSIVE TERMS - SEMI-IMPLICIT EULER
        # use u0 = u^(n+1) to evaluate tendencies, add to u0 = u^n + rhs
        # evaluate only every nstep_diff time steps
        if (S_true.parameters.i % nstep_diff) == 0
            ShallowWaters.bottom_drag!(u0rhs,v0rhs,η0rhs,Diag,S_true)
            ShallowWaters.diffusion!(u0rhs,v0rhs,Diag,S_true)
            ShallowWaters.add_drag_diff_tendencies!(u0,v0,Diag,S_true)
            ShallowWaters.ghost_points_uv!(u0,v0,S_true)
        end

        # TRACER ADVECTION
        u0rhs = convert(Diag.PrognosticVarsRHS.u,u0) 
        v0rhs = convert(Diag.PrognosticVarsRHS.v,v0)
        ShallowWaters.tracer!(i,u0rhs,v0rhs,Prog,Diag,S_true)

        # if t ∈ 30*225:30*225:S_true.grid.nt
            temp1 = ShallowWaters.PrognosticVars{S_true.parameters.Tprog}(
                ShallowWaters.remove_halo(u,v,η,sst,S_true)...)
            push!(true_states, temp1)
        # end

        if t ∈ S_true.parameters.data_steps
            temp2 = u_mat_to_vec((ShallowWaters.PrognosticVars{S_true.parameters.Tprog}(
                ShallowWaters.remove_halo(u,v,η,sst,S_true)...)).u
            )
            data[:, j] = Float32.(temp2[data_spots] .+ sigma_data .* randn(length(data_spots)))
            j += 1
        end

        # Copy back from substeps
        copyto!(u,u0)
        copyto!(v,v0)
        copyto!(η,η0)

        t += dtint

    end

    return data, true_states

end

function finite_difference_only(dS,x_coord,y_coord;kwargs...)

    enzyme_deriv = dS.Prog.u[x_coord,y_coord]

    steps = [50, 40, 30, 20, 10, 1, 1e-1, 1e-2, 1e-3, 1e-4, 1e-5, 1e-6, 1e-7, 1e-8, 1e-9]

    P = ShallowWaters.Parameter(T=dS.parameters.T;kwargs...)
    S_outer = ShallowWaters.model_setup(P)

    snaps = Int(floor(sqrt(S_outer.grid.nt)))
    revolve = Revolve{ShallowWaters.ModelSetup}(S_outer.grid.nt, snaps;
        verbose=1,
        gc=true,
        write_checkpoints=false
    )

    J_outer = integration(S_outer)

    diffs = []

    for s in steps

        S_inner = ShallowWaters.model_setup(output=false,
        L_ratio=1,
        g=9.81,
        H=500,
        wind_forcing_x="double_gyre",
        Lx=3840e3,
        seasonal_wind_x=false,
        topography="flat",
        bc="nonperiodic",
        bottom_drag="quadratic",
        α=2,
        # νB=1000,
        nx=128,
        Ndays=30,
        # initial_cond="ncfile",
        # initpath="./run_0001/"
        )
        S_inner.Prog.u[x_coord, y_coord] += s

        # J_inner = checkpointed_integration(S_inner, revolve)
        J_inner = integration(S_inner)

        push!(diffs, (J_inner - J_outer) / s)

    end

    return diffs, enzyme_deriv

end