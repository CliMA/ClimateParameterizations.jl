function prepare_parameters_NDE_training(𝒟train, uw_NN, vw_NN, wT_NN, f, Nz, g, α, ν₀, ν₋, Riᶜ, ΔRi, Pr, κ, conditions)
    H = abs(𝒟train.uw.z[end] - 𝒟train.uw.z[1])
    τ = abs(𝒟train.t[:,1][end] - 𝒟train.t[:,1][1])
    u_scaling = 𝒟train.scalings["u"]
    v_scaling = 𝒟train.scalings["v"]
    T_scaling = 𝒟train.scalings["T"]
    uw_scaling = 𝒟train.scalings["uw"]
    vw_scaling = 𝒟train.scalings["vw"]
    wT_scaling = 𝒟train.scalings["wT"]

    uw_weights, re_uw = Flux.destructure(uw_NN)
    vw_weights, re_vw = Flux.destructure(vw_NN)
    wT_weights, re_wT = Flux.destructure(wT_NN)

    size_uw_NN = length(uw_weights)
    size_vw_NN = length(vw_weights)
    size_wT_NN = length(wT_weights)

    uw_range = 1:size_uw_NN
    vw_range = size_uw_NN + 1:size_uw_NN + size_vw_NN
    wT_range = size_uw_NN + size_vw_NN + 1:size_uw_NN + size_vw_NN + size_wT_NN

    if conditions.modified_pacanowski_philander
        constants = (H=H, τ=τ, f=f, Nz=Nz, g=g, α=α, ν₀=ν₀, ν₋=ν₋, Riᶜ=Riᶜ, ΔRi=ΔRi, Pr=Pr)
    elseif conditions.convective_adjustment
        constants = (H=H, τ=τ, f=f, Nz=Nz, g=g, α=α, κ=κ)
    else
        constants = (H=H, τ=τ, f=f, Nz=Nz, g=g, α=α)
    end
    scalings = (u=u_scaling, v=v_scaling, T=T_scaling, uw=uw_scaling, vw=vw_scaling, wT=wT_scaling)
    derivatives = (cell=Float32.(Dᶜ(Nz, 1 / Nz)), face=Float32.(Dᶠ(Nz, 1 / Nz)))
    NN_constructions = (uw=re_uw, vw=re_vw, wT=re_wT)
    weights = Float32[uw_weights; vw_weights; wT_weights]

    NN_sizes = (uw=size_uw_NN, vw=size_vw_NN, wT=size_wT_NN)
    NN_ranges = (uw=uw_range, vw=vw_range, wT=wT_range)

    filters = (cell=WindMixing.smoothing_filter(Nz, 3), face=WindMixing.smoothing_filter(Nz+1, 3), interior=WindMixing.smoothing_filter(Nz-1, 3))
    return constants, scalings, derivatives, NN_constructions, weights, NN_sizes, NN_ranges, filters
end

function local_richardson(∂u∂z, ∂v∂z, ∂T∂z, H, g, α, σ_u, σ_v, σ_T)
    # H, g, α = constants.H, constants.g, constants.α
    # σ_u, σ_v, σ_T = scalings.u.σ, scalings.v.σ, scalings.T.σ
    Bz = H * g * α * σ_T * ∂T∂z
    S² = (σ_u * ∂u∂z) ^2 + (σ_v * ∂v∂z) ^2
    return Bz / S²
end

tanh_step(x) = (1 - tanh(x)) / 2

function NDE(x, p, t, NN_ranges, NN_constructions, conditions, scalings, constants, derivatives, filters)
    uw_range, vw_range, wT_range = NN_ranges.uw, NN_ranges.vw, NN_ranges.wT
    uw_weights, vw_weights, wT_weights = p[uw_range], p[vw_range], p[wT_range]
    uw_bottom, uw_top, vw_bottom, vw_top, wT_bottom, wT_top = p[wT_range[end] + 1:end]
    BCs = (uw=(top=uw_top, bottom=uw_bottom), vw=(top=vw_top, bottom=vw_bottom), wT=(top=wT_top, bottom=wT_bottom))
    re_uw, re_vw, re_wT = NN_constructions.uw, NN_constructions.vw, NN_constructions.wT
    uw_NN = re_uw(uw_weights)
    vw_NN = re_vw(vw_weights)
    wT_NN = re_wT(wT_weights)
    return predict_NDE(uw_NN, vw_NN, wT_NN, x, BCs, conditions, scalings, constants, derivatives, filters)
end

function predict_NDE(uw_NN, vw_NN, wT_NN, x, BCs, conditions, scalings, constants, derivatives, filters)
    Nz, H, τ, f = constants.Nz, constants.H, constants.τ, constants.f
    uw_scaling, vw_scaling, wT_scaling = scalings.uw, scalings.vw, scalings.wT
    σ_uw, σ_vw, σ_wT = uw_scaling.σ, vw_scaling.σ, wT_scaling.σ
    μ_u, μ_v, σ_u, σ_v, σ_T = scalings.u.μ, scalings.v.μ, scalings.u.σ, scalings.v.σ, scalings.T.σ
    D_cell, D_face = derivatives.cell, derivatives.face

    u = @view x[1:Nz]
    v = @view x[Nz + 1:2Nz]
    T = @view x[2Nz + 1:3Nz]
    
    if conditions.zero_weights
        uw = uw_NN(x)
        vw = vw_NN(x)
        wT = wT_NN(x)

        if conditions.smooth_NN
            uw = filters.face * uw
            vw = filters.face * vw
            wT = filters.face * wT
        end
    else
        # uw_interior = uw_NN(x)
        # vw_interior = vw_NN(x)
        # wT_interior = wT_NN(x)

        uw_interior = fill(uw_scaling(0f0), Nz-1)
        vw_interior = fill(vw_scaling(0f0), Nz-1)
        wT_interior = fill(wT_scaling(0f0), Nz-1)

        if conditions.smooth_NN
            uw_interior = filters.interior * uw_interior
            vw_interior = filters.interior * vw_interior
            wT_interior = filters.interior * wT_interior
        end

        uw = [BCs.uw.bottom; uw_interior; BCs.uw.top]
        vw = [BCs.vw.bottom; vw_interior; BCs.vw.top]
        wT = [BCs.wT.bottom; wT_interior; BCs.wT.top]
    end

    if conditions.modified_pacanowski_philander
        ϵ = 1f-7
        ∂u∂z = D_face * u
        ∂v∂z = D_face * v
        ∂T∂z = D_face * T
        Ri = local_richardson.(∂u∂z .+ ϵ, ∂v∂z .+ ϵ, ∂T∂z .+ ϵ, constants.H, constants.g, constants.α, scalings.u.σ, scalings.v.σ, scalings.T.σ)

        if conditions.smooth_Ri
            Ri = filters.face * Ri
        end

        ν = constants.ν₀ .+ constants.ν₋ .* tanh_step.((Ri .- constants.Riᶜ) ./ constants.ΔRi)

        if conditions.zero_weights
            ν∂u∂z = [[-H * σ_uw / σ_u * (BCs.uw.bottom - scalings.uw(0f0))]; ν[2:end-1] .* ∂u∂z[2:end-1]; [-H * σ_uw / σ_u * (BCs.uw.top - scalings.uw(0f0))]]
            ν∂v∂z = [[-H * σ_vw / σ_v * (BCs.vw.bottom - scalings.vw(0f0))]; ν[2:end-1] .* ∂v∂z[2:end-1]; [-H * σ_vw / σ_v * (BCs.vw.top - scalings.vw(0f0))]]
            ν∂T∂z = [[-H * σ_wT / σ_T * (BCs.wT.bottom - scalings.wT(0f0))]; ν[2:end-1] ./ constants.Pr .* ∂T∂z[2:end-1]; [-H * σ_wT / σ_T * (BCs.wT.top - scalings.wT(0f0))]]

            ∂z_ν∂u∂z = D_cell * ν∂u∂z
            ∂z_ν∂v∂z = D_cell * ν∂v∂z
            ∂z_ν∂T∂z = D_cell * ν∂T∂z
        else
            ∂z_ν∂u∂z = D_cell * (ν .* ∂u∂z)
            ∂z_ν∂v∂z = D_cell * (ν .* ∂v∂z)
            ∂z_ν∂T∂z = D_cell * (ν .* ∂T∂z ./ constants.Pr)
        end

        ∂u∂t = -τ / H * σ_uw / σ_u .* D_cell * uw .+ f * τ / σ_u .* (σ_v .* v .+ μ_v) .+ τ / H ^ 2 .* ∂z_ν∂u∂z
        ∂v∂t = -τ / H * σ_vw / σ_v .* D_cell * vw .- f * τ / σ_v .* (σ_u .* u .+ μ_u) .+ τ / H ^ 2 .* ∂z_ν∂v∂z
        ∂T∂t = -τ / H * σ_wT / σ_T .* D_cell * wT .+ τ / H ^ 2 .* ∂z_ν∂T∂z
    elseif conditions.convective_adjustment
        ∂u∂t = -τ / H * σ_uw / σ_u .* D_cell * uw .+ f * τ / σ_u .* (σ_v .* v .+ μ_v)
        ∂v∂t = -τ / H * σ_vw / σ_v .* D_cell * vw .- f * τ / σ_v .* (σ_u .* u .+ μ_u)
        ∂T∂z = D_face * T
        ∂z_κ∂T∂z = D_cell * (κ .* min.(0f0, ∂T∂z))
        ∂T∂t = -τ / H * σ_wT / σ_T .* D_cell * wT .+ τ / H ^2 .* ∂z_κ∂T∂z
    else
        ∂u∂t = -τ / H * σ_uw / σ_u .* D_cell * uw .+ f * τ / σ_u .* (σ_v .* v .+ μ_v)
        ∂v∂t = -τ / H * σ_vw / σ_v .* D_cell * vw .- f * τ / σ_v .* (σ_u .* u .+ μ_u)
        ∂T∂t = -τ / H * σ_wT / σ_T .* D_cell * wT
    end

    return [∂u∂t; ∂v∂t; ∂T∂t]
end

function train_NDE(uw_NN, vw_NN, wT_NN, 𝒟train, tsteps, timestepper, optimizers, epochs, FILE_PATH, stage; 
                    n_simulations, maxiters=500, ν₀=1f-4, ν₋=1f-1, ΔRi=1f0, Riᶜ=0.25, Pr=1f0, κ=10f0, f=1f-4, α=1.67f-4, g=9.81f0, 
                    modified_pacanowski_philander=false, convective_adjustment=false, smooth_profile=false, smooth_NN=false, smooth_Ri=false, train_gradient=false,
                    zero_weights=false)
    @assert !modified_pacanowski_philander || !convective_adjustment

    if zero_weights
        @assert modified_pacanowski_philander
    end

    Nz = length(𝒟train.u.z)

    conditions = (modified_pacanowski_philander=modified_pacanowski_philander, convective_adjustment=convective_adjustment, 
                    smooth_profile=smooth_profile, smooth_NN=smooth_NN, smooth_Ri=smooth_Ri, 
                    train_gradient=train_gradient, zero_weights=zero_weights)
    
    constants, scalings, derivatives, NN_constructions, weights, NN_sizes, NN_ranges, filters = prepare_parameters_NDE_training(𝒟train, uw_NN, vw_NN, wT_NN, f, Nz, g, α, ν₀, ν₋, Riᶜ, ΔRi, Pr, κ, conditions)

    n_steps = Int(length(@view(𝒟train.t[:,1])) / n_simulations)

    uvT₀s = [𝒟train.uvT_scaled[:,n_steps * i + tsteps[1]] for i in 0:n_simulations - 1]
    t_train = 𝒟train.t[:,1][tsteps]
    uvT_trains = [𝒟train.uvT_scaled[:,n_steps * i + 1:n_steps * (i + 1)][:, tsteps] for i in 0:n_simulations - 1]

    # D_face_uvT = [D_face; D_face; D_face]
    # function calculate_gradient(uvTs)
    #     Nzf = Nz + 1
    #     gradients = [zeros(Float32, size(uvT, 1) + 3, size(uvT, 2)) for uvT in uvTs]
    #     for i in 1:length(gradients)
    #         gradient = gradients[i]
    #         uvT = uvTs[i]
    #         for j in 1:size(gradient, 2)
    #             # ∂u∂z = @view gradient[1:Nzf, j]
    #             # ∂v∂z = @view gradient[Nzf+1:2Nzf, j]
    #             # ∂T∂z = @view gradient[2Nzf+1:end, j]

    #             # gradient[1:Nzf, j] = D_face * uvT[1:Nz, j]
    #             # gradient[Nzf+1:2Nzf, j] = D_face * uvT[Nz+1:2Nz, j]
    #             # gradient[2Nzf+1:end, j] = D_face * uvT[2Nz+1:3Nz, j]
    #             gradient[:,j] = D_face_uvT * uvT[:,j]
    #         end
    #     end
    #     return gradients
    # end

    function calculate_gradient(uvTs)
        return cat([cat([[D_face * uvT[1:Nz, i]; D_face * uvT[Nz+1:2Nz, i]; D_face * uvT[2Nz+1:3Nz, i]] for i in 1:size(uvT, 2)]..., dims=2) for uvT in uvTs]..., dims=2)
    end

    if train_gradient
        uvT_gradients = calculate_gradient(uvT_trains)
    end

    prob_NDE(x, p, t) = NDE(x, p, t, NN_ranges, NN_constructions, conditions, scalings, constants, derivatives, filters)

    t_train = t_train ./ constants.τ
    tspan_train = (t_train[1], t_train[end])
    BCs = [[𝒟train.uw.scaled[1,n_steps * i + tsteps[1]],
            𝒟train.uw.scaled[end,n_steps * i + tsteps[1]],
            𝒟train.vw.scaled[1,n_steps * i + tsteps[1]],
            𝒟train.vw.scaled[end,n_steps * i + tsteps[1]],
            𝒟train.wT.scaled[1,n_steps * i + tsteps[1]],
            𝒟train.wT.scaled[end,n_steps * i + tsteps[1]]] for i in 0:n_simulations - 1]

    prob_NDEs = [ODEProblem(prob_NDE, uvT₀s[i], tspan_train) for i in 1:n_simulations]

    function loss(weights, BCs)
        sols = [Array(solve(prob_NDEs[i], timestepper, p=[weights; BCs[i]], reltol=1f-3, sensealg=InterpolatingAdjoint(autojacvec=ZygoteVJP()), saveat=t_train)) for i in 1:n_simulations]        
        return mean(Flux.mse.(sols, uvT_trains))
    end

    function loss_gradient(weights, BCs)
        sols = [Array(solve(prob_NDEs[i], timestepper, p=[weights; BCs[i]], reltol=1f-3, sensealg=InterpolatingAdjoint(autojacvec=ZygoteVJP()), saveat=t_train)) for i in 1:n_simulations]
        loss_profile = mean(Flux.mse.(sols, uvT_trains))
        loss_gradient = mean(Flux.mse.(calculate_gradient(sols), uvT_gradients))
        return mean([loss_profile, loss_gradient])
    end

    if train_gradient
        f_loss = OptimizationFunction(loss_gradient, GalacticOptim.AutoZygote())
        prob_loss = OptimizationProblem(f_loss, weights, BCs)
    else
        f_loss = OptimizationFunction(loss, GalacticOptim.AutoZygote())
        prob_loss = OptimizationProblem(f_loss, weights, BCs)
    end

    for i in 1:length(optimizers), epoch in 1:epochs
        iter = 1
        opt = optimizers[i]
        function cb(args...)
            if iter <= maxiters
                @info "NDE, loss = $(args[2]), stage $stage, optimizer $i/$(length(optimizers)), epoch $epoch/$epochs, iteration = $iter/$maxiters"
                write_data_NDE_training(FILE_PATH, args[2], NN_constructions.uw(args[1][NN_ranges.uw]), NN_constructions.vw(args[1][NN_ranges.vw]), NN_constructions.wT(args[1][NN_ranges.wT]), stage)
            end
            iter += 1
            false
        end
        res = solve(prob_loss, opt, cb=cb, maxiters=maxiters)
        weights .= res.minimizer
    end
    return NN_constructions.uw(weights[NN_ranges.uw]), NN_constructions.vw(weights[NN_ranges.vw]), NN_constructions.wT(weights[NN_ranges.wT])
end