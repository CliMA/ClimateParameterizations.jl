"""
Adapted from
https://github.com/sandreza/OceanConvectionUQSupplementaryMaterials/blob/master/src/ForwardMap/fm.jl
updated for latest version of OceanTurb
"""

"""
closure_free_convection_kpp_full_evolution(parameters, D, Δt, les::LESbraryData; subsample = 1, grid = 1)

Constructs forward map. Assumes initial conditions and boundary conditions are taken from les data.

# Arguments
- `N`: number of gridpoints to output to
- `Δt`: time step size in seconds
- `les`: les data of the LESbraryData type

# Keyword Arguments
- `subsample`: indices to subsample in time,
- `grid`: in case one wants to save the model grid

# Output
- The forward map. A function that takes parameters and outputs temperature profiles
-   `𝑪`: parameters in KPP, assumes that
    𝑪[1]: Surface Layer Fraction
    𝑪[2]: Nonlocal Flux Amplitude
    𝑪[3]: Diffusivity Amplitude
    𝑪[4]: Shear Constant
"""
function closure_kpp_full_evolution(parameters, D, Δt, les; subsample = 1, grid = 1)

     # set parameters
     # parameters = KPP.Parameters( CSL = 𝑪[1], CNL = 𝑪[2], Cb_T = 𝑪[3], CKE = 𝑪[4])

     # Build the model with a Backward Euler timestepper
     constants = Constants(Float64; α = les.α , β = les.β, f=les.fᶿ, g=les.g)
     model = KPP.Model(grid = UniformGrid(N, les.L), stepper=:BackwardEuler, constants = constants, parameters = parameters)

     # Get grid if necessary
     if grid != 1
         zp = collect(model.grid.zc)
         @. grid  = zp
     end

     # Set boundary conditions
     model.bcs.u.top    = FluxBoundaryCondition(u_top)
     model.bcs.u.bottom = FluxBoundaryCondition(u_bottom)
     model.bcs.b.top    = FluxBoundaryCondition(θ_top)
     model.bcs.b.bottom = FluxBoundaryCondition(θ_bottom) # may need to fix

    # define the closure
    function evolve()

        # get average of initial condition of LES
        T⁰ = custom_avg(les.T⁰, D)

        # set equal to initial condition of parameterization
        model.solution.T[1:D] = copy(T⁰)

        # set aside memory
        if subsample != 1
            time_index = subsample
        else
            time_index = 1:length(les.t)
        end
        Nt = length(les.t[time_index])
        𝒢 = zeros(D, Nt)

        # loop the model
        ti = collect(time_index)
        for i in 1:Nt
            t = les.t[ti[i]]
            run_until!(model, Δt, t)
            @. 𝒢[:,i] = model.solution.T[1:D]
        end
        return 𝒢
    end
    return evolve
end
