using Statistics
using NCDatasets
using Plots
using Flux
using OceanParameterizations
using Oceananigans.Grids
using BSON
using OrdinaryDiffEq, DiffEqSensitivity
include("lesbrary_data.jl")
include("data_containers.jl")
include("animate_prediction.jl")


# train_files = ["free_convection", "strong_wind", "weak_wind_strong_cooling"]
train_files = ["strong_wind"]
output_gif_directory = "Output"



𝒟train = data(train_files,
                    scale_type=ZeroMeanUnitVarianceScaling,
                    animate=false,
                    animate_dir="$(output_gif_directory)/Training")


function animate_NN(xs, y, t, x_str, x_label=["" for i in length(xs)], filename=x_str)
    PATH = joinpath(pwd(), "Output")
    anim = @animate for n in 1:size(xs[1],2)
    x_max = maximum(maximum(x) for x in xs)
    x_min = minimum(minimum(x) for x in xs)
        @info "$x_str frame of $n/$(size(xs[1],2))"
        fig = plot(xlim=(x_min, x_max), ylim=(minimum(y), maximum(y)), legend=:bottom)
        for i in 1:length(xs)
            plot!(fig, xs[i][:,n], y, label=x_label[i], title="t = $(round(t[n]/86400, digits=2)) days")
        end
        xlabel!(fig, "$x_str")
        ylabel!(fig, "z")
    end
    gif(anim, joinpath(PATH, "$(filename).gif"), fps=30)
end
# function append_parameters(𝒟, datanames)
#     filenames = Dict(
#         "free_convection"          => 1,
#         "strong_wind"              => 2,
#         "strong_wind_weak_cooling" => 3,
#         "weak_wind_strong_cooling" => 4,
#         "strong_wind_weak_heating" => 5,
#         "strong_wind_no_coriolis"  => 6,
#     )
#     # momentum_fluxes = [0., -1e-3, -8e-4, -3e-4, -1e-3, -2e-4]
#     # momentum_fluxes_scaling = ZeroMeanUnitVarianceScaling(momentum_fluxes)
#     # momentum_fluxes_scaled = scale(momentum_fluxes, momentum_fluxes_scaling)

#     # buoyancy_fluxes = [1.2e-7, 0., 3e-8, 1e-7, -4e-8, 0.]
#     # buoyancy_fluxes_scaling = ZeroMeanUnitVarianceScaling(buoyancy_fluxes)
#     # buoyancy_fluxes_scaled = scale(buoyancy_fluxes, buoyancy_fluxes_scaling)

#     fs = [1e-4, 1e-4, 1e-4, 1e-4, 1e-4, 0.]
#     fs_scaling = ZeroMeanUnitVarianceScaling(fs)
#     fs_scaled = scale(fs, fs_scaling)

#     datalength = Int(size(𝒟.uvT_scaled,2) / length(datanames))
#     # output = Array{Float64}(undef, size(𝒟.uvT_scaled,1)+3, size(𝒟.uvT_scaled,2))
#     output = Array{Float64}(undef, size(𝒟.uvT_scaled,1)+1, size(𝒟.uvT_scaled,2))
#     uvT = @view output[2:end, :]
#     uvT .= 𝒟.uvT_scaled


#     for i in 1:length(datanames)
#         dataname = datanames[i]
#         coriolis_row = @view output[1, (i-1)*datalength+1:i*datalength]
#         # momentum_row = @view output[2, (i-1)*datalength+1:i*datalength]
#         # buoyancy_row = @view output[3, (i-1)*datalength+1:i*datalength]
#         coriolis_row .= fs_scaled[filenames[dataname]]
#         # momentum_row .= momentum_fluxes_scaled[filenames[dataname]]
#         # buoyancy_row .= buoyancy_fluxes_scaled[filenames[dataname]]
#     end
#     return [(output[:,i], 𝒟.uw.scaled) for i in 1:size(output,2)], [(output[:,i], 𝒟.vw.scaled) for i in 1:size(output,2)], [(output[:,i], 𝒟.wT.scaled) for i in 1:size(output,2)]
# end

function prepare_training_data(input, truth)
    return [(input[:,i], truth[:,i]) for i in 1:size(truth, 2)]
end

uw_train = prepare_training_data(𝒟train.uvT_scaled, 𝒟train.uw.scaled)
vw_train = prepare_training_data(𝒟train.uvT_scaled, 𝒟train.vw.scaled)
wT_train = prepare_training_data(𝒟train.uvT_scaled, 𝒟train.wT.scaled)


N_inputs = 96
N_outputs = 31
uw_NN_model = Chain(Dense(N_inputs, N_inputs, relu), Dense(N_inputs, N_inputs, relu), Dense(N_inputs,N_outputs))
vw_NN_model = Chain(Dense(N_inputs, N_inputs, relu), Dense(N_inputs, N_inputs, relu), Dense(N_inputs,N_outputs))
wT_NN_model = Chain(Dense(N_inputs, N_inputs, relu), Dense(N_inputs, N_inputs, relu), Dense(N_inputs,N_outputs))

function predict(NN, x, y)
    interior = NN(x)
    return [y[1]; interior; y[end]]
end

predict(uw_NN_model, uw_train[1][1], uw_train[1][2])
Flux.Losses.mse(predict(uw_NN_model, uw_train[1][1], uw_train[1][2]), uw_train[1][2])
# uw_train[1][1]
# uw_NN_model(uw_train[1][1])

loss_uw(x, y) = Flux.Losses.mse(predict(uw_NN_model, x, y), y)
loss_vw(x, y) = Flux.Losses.mse(predict(vw_NN_model, x, y), y)
loss_wT(x, y) = Flux.Losses.mse(predict(wT_NN_model, x, y), y)

function train_NN(NN, loss, data, opts)
    function cb()
        @info "loss = $(mean([loss(data[i][1], data[i][2]) for i in 1:length(data)]))"
    end
   for opt in opts
        Flux.train!(loss, params(NN), data, opt, cb=Flux.throttle(cb, 2))
    end 
end

# optimizers = [ADAM(), ADAM(), ADAM(), ADAM(), ADAM(), ADAM(), ADAM(), ADAM(), ADAM(), ADAM(), ADAM(), ADAM(), 
# Descent(), Descent(), Descent(), Descent(), Descent(), Descent(), Descent(), Descent(), Descent(), Descent(), Descent(), Descent(), Descent(), Descent(), Descent()]
# optimizers = [ADAM(), ADAM(), ADAM(), Descent(), Descent(), Descent()]
optimizers = [Descent()]


train_NN(uw_NN_model, loss_uw, uw_train, optimizers)
train_NN(vw_NN_model, loss_vw, vw_train, optimizers)
train_NN(wT_NN_model, loss_wT, wT_train, optimizers)

@info "loss = $(mean([loss_uw(uw_train[i][1], uw_train[i][2]) for i in 1:length(uw_train)]))"
@info "loss = $(mean([loss_vw(vw_train[i][1], vw_train[i][2]) for i in 1:length(vw_train)]))"
@info "loss = $(mean([loss_wT(wT_train[i][1], wT_train[i][2]) for i in 1:length(wT_train)]))"

uw_NN_params = Dict(
    :neural_network => uw_NN_model)

bson("uw_NN_params_2DaySuite.bson", uw_NN_params)

vw_NN_params = Dict(
    :neural_network => vw_NN_model)

bson("vw_NN_params_2DaySuite.bson", vw_NN_params)


wT_NN_params = Dict(
    :neural_network => wT_NN_model)

bson("wT_NN_params_2DaySuite.bson", wT_NN_params)


NN_prediction_uw = cat((predict(uw_NN_model, uw_train[i][1], uw_train[i][2]) for i in 1:length(uw_train))..., dims=2)
truth_uw = cat((uw_train[i][2] for i in 1:length(uw_train))..., dims=2)
uw_plots = (NN_prediction_uw, truth_uw)

NN_prediction_vw = cat((predict(vw_NN_model, vw_train[i][1], vw_train[i][2]) for i in 1:length(vw_train))..., dims=2)
truth_vw = cat((vw_train[i][2] for i in 1:length(vw_train))..., dims=2)
vw_plots = (NN_prediction_vw, truth_vw)


NN_prediction_wT = cat((predict(wT_NN_model, wT_train[i][1], wT_train[i][2]) for i in 1:length(wT_train))..., dims=2)
truth_wT = cat((wT_train[i][2] for i in 1:length(wT_train))..., dims=2)
wT_plots = (NN_prediction_wT, truth_wT)

animate_NN(uw_plots, 𝒟train.uw.z, 𝒟train.t[:,1], "uw", ["NN", "truth"], "uw_strong_wind_bounds1")
animate_NN(vw_plots, 𝒟train.vw.z, 𝒟train.t[:,1], "vw", ["NN", "truth"], "vw_strong_wind_bounds1")
animate_NN(wT_plots, 𝒟train.wT.z, 𝒟train.t[:,1], "wT", ["NN", "truth"], "wT_strong_wind_bounds")

𝒟train.uvT_scaled
𝒟train.uw.scaled

function predict_NDE(NN, x, top, bottom)
    interior = NN(x)
    return [top; interior; bottom]
end

f = 1f-4
H = Float32(abs(𝒟train.uw.z[end] - 𝒟train.uw.z[1]))
τ = Float32(abs(𝒟train.t[:,1][end] - 𝒟train.t[:,1][1]))
Nz = 32
u_scaling = 𝒟train.scalings["u"]
v_scaling = 𝒟train.scalings["v"]
T_scaling = 𝒟train.scalings["T"]
uw_scaling = 𝒟train.scalings["uw"]
vw_scaling = 𝒟train.scalings["vw"]
wT_scaling = 𝒟train.scalings["wT"]
μ_u = Float32(u_scaling.μ)
μ_v = Float32(v_scaling.μ)
σ_u = Float32(u_scaling.σ)
σ_v = Float32(v_scaling.σ)
σ_T = Float32(T_scaling.σ)
σ_uw = Float32(uw_scaling.σ)
σ_vw = Float32(vw_scaling.σ)
σ_wT = Float32(wT_scaling.σ)
uw_weights, re_uw = Flux.destructure(uw_NN_model)
vw_weights, re_vw = Flux.destructure(vw_NN_model)
wT_weights, re_wT = Flux.destructure(wT_NN_model)
uw_top = Float32(𝒟train.uw.scaled[1,1])
uw_bottom = Float32(uw_scaling(-1e-3))
vw_top = Float32(𝒟train.vw.scaled[1,1])
vw_bottom = Float32(𝒟train.vw.scaled[end,1])
wT_top = Float32(𝒟train.wT.scaled[1,1])
wT_bottom = Float32(𝒟train.wT.scaled[end,1])
size_uw_NN = length(uw_weights)
size_vw_NN = length(vw_weights)
size_wT_NN = length(wT_weights)
p_nondimensional = [f; τ; H; μ_u; μ_v; σ_u; σ_v; σ_T; σ_uw; σ_vw; σ_wT; uw_top; uw_bottom; vw_top; vw_bottom; wT_top; wT_bottom; uw_weights; vw_weights; wT_weights]

D_cell = Float32.(Dᶜ(Nz, 1/Nz))

function NDE_nondimensional_flux!(dx, x, p, t)
    f, τ, H, μ_u, μ_v, σ_u, σ_v, σ_T, σ_uw, σ_vw, σ_wT, uw_top, uw_bottom, vw_top, vw_bottom, wT_top, wT_bottom = p[1:17]
    Nz = 32
    uw_weights = p[18:18+size_uw_NN-1]
    vw_weights = p[18+size_uw_NN:18+size_uw_NN+size_vw_NN-1]
    wT_weights = p[18+size_uw_NN+size_vw_NN:end]
    uw_NN = re_uw(uw_weights)
    vw_NN = re_vw(vw_weights)
    wT_NN = re_wT(wT_weights)
    A = - τ / H
    B = f * τ
    u = x[1:Nz]
    v = x[Nz+1:2*Nz]
    T = x[2*Nz+1:end]
    dx[1:Nz] .= A .* σ_uw ./ σ_u .* D_cell * predict_NDE(uw_NN, x, uw_top, uw_bottom) .+ B ./ σ_u .* (σ_v .* v .+ μ_v) #nondimensional gradient
    dx[Nz+1:2*Nz] .= A .* σ_vw ./ σ_v .* D_cell * predict_NDE(vw_NN, x, vw_top, vw_bottom) .- B ./ σ_v .* (σ_u .* u .+ μ_u)
    dx[2*Nz+1:end] .= A .* σ_wT ./ σ_T .* D_cell * predict_NDE(wT_NN, x, wT_top, wT_bottom)
end

function time_window(t, uvT; startindex=1, stopindex)
    if stopindex < length(t)
        return (Float32.(t[startindex:stopindex]), Float32.(uvT[:,startindex:stopindex]))
    else
        @info "stop index larger than length of t"
    end
end

start_index = 1
end_index = 10
uvT₀ = Float32.(𝒟train.uvT_scaled[:,start_index])
tspan_train = (0f0, Float32.((𝒟train.t[end_index] - 𝒟train.t[start_index])/τ))

t_train, uvT_train = time_window(𝒟train.t, 𝒟train.uvT_scaled, startindex=start_index, stopindex=end_index)
t_train = Float32.(t_train ./ τ)

opt_NDE = ROCK4()
prob = ODEProblem(NDE_nondimensional_flux!, uvT₀, tspan_train, p_nondimensional, saveat=t_train)
sol = solve(prob, opt_NDE)

function loss_NDE_NN()
    p=[f; τ; H; μ_u; μ_v; σ_u; σ_v; σ_T; σ_uw; σ_vw; σ_wT; uw_top; uw_bottom; vw_top; vw_bottom; wT_top; wT_bottom; uw_weights; vw_weights; wT_weights]
    _sol = Array(solve(prob, opt_NDE, p=p, reltol=1f-3, sense=InterpolatingAdjoint(autojacvec=ZygoteVJP())))
    loss = Flux.mse(_sol, uvT_train)
    return loss
end

loss_NDE_NN()

function cb_NDE()
    p=[f; τ; H; μ_u; μ_v; σ_u; σ_v; σ_T; σ_uw; σ_vw; σ_wT; uw_top; uw_bottom; vw_top; vw_bottom; wT_top; wT_bottom; uw_weights; vw_weights; wT_weights]
    _sol = Array(solve(prob, opt_NDE, p=p, sense=InterpolatingAdjoint(autojacvec=ZygoteVJP())))
    loss = Flux.mse(_sol, uvT_train)
    @info loss
    return _sol
end

Flux.train!(loss_NDE_NN, Flux.params(uw_weights, vw_weights, wT_weights), Iterators.repeated((), 2), ADAM(0.01), cb=Flux.throttle(cb_NDE,2))
cb_NDE()

function train_NDE(𝒟train, uw_NN_model, vw_NN_model, wT_NN_model, epochs=2, opt_NDE=ROCK4())
    f = 1f-4
    H = Float32(abs(𝒟train.uw.z[end] - 𝒟train.uw.z[1]))
    τ = Float32(abs(𝒟train.t[:,1][end] - 𝒟train.t[:,1][1]))
    Nz = 32
    u_scaling = 𝒟train.scalings["u"]
    v_scaling = 𝒟train.scalings["v"]
    T_scaling = 𝒟train.scalings["T"]
    uw_scaling = 𝒟train.scalings["uw"]
    vw_scaling = 𝒟train.scalings["vw"]
    wT_scaling = 𝒟train.scalings["wT"]
    μ_u = Float32(u_scaling.μ)
    μ_v = Float32(v_scaling.μ)
    σ_u = Float32(u_scaling.σ)
    σ_v = Float32(v_scaling.σ)
    σ_T = Float32(T_scaling.σ)
    σ_uw = Float32(uw_scaling.σ)
    σ_vw = Float32(vw_scaling.σ)
    σ_wT = Float32(wT_scaling.σ)
    uw_weights, re_uw = Flux.destructure(uw_NN_model)
    vw_weights, re_vw = Flux.destructure(vw_NN_model)
    wT_weights, re_wT = Flux.destructure(wT_NN_model)
    uw_top = Float32(𝒟train.uw.scaled[1,1])
    uw_bottom = Float32(uw_scaling(-1f-3))
    vw_top = Float32(𝒟train.vw.scaled[1,1])
    vw_bottom = Float32(𝒟train.vw.scaled[end,1])
    wT_top = Float32(𝒟train.wT.scaled[1,1])
    wT_bottom = Float32(𝒟train.wT.scaled[end,1])
    size_uw_NN = length(uw_weights)
    size_vw_NN = length(vw_weights)
    size_wT_NN = length(wT_weights)
    p_nondimensional = [f; τ; H; μ_u; μ_v; σ_u; σ_v; σ_T; σ_uw; σ_vw; σ_wT; uw_top; uw_bottom; vw_top; vw_bottom; wT_top; wT_bottom; uw_weights; vw_weights; wT_weights]
    D_cell = Float32.(Dᶜ(Nz, 1/Nz))

    start_index = 1
    end_index = 10
    uvT₀ = Float32.(𝒟train.uvT_scaled[:,start_index])
    tspan_train = (0f0, Float32.((𝒟train.t[end_index] - 𝒟train.t[start_index])/τ))

    t_train, uvT_train = time_window(𝒟train.t, 𝒟train.uvT_scaled, startindex=start_index, stopindex=end_index)
    t_train ./= τ

    function predict_NDE(NN, x, top, bottom)
        interior = NN(x)
        return [top; interior; bottom]
    end


    function NDE_nondimensional_flux!(dx, x, p, t)
        f, τ, H, μ_u, μ_v, σ_u, σ_v, σ_T, σ_uw, σ_vw, σ_wT, uw_top, uw_bottom, vw_top, vw_bottom, wT_top, wT_bottom = p[1:17]
        Nz = 32
        uw_weights = p[18:18+size_uw_NN-1]
        vw_weights = p[18+size_uw_NN:18+size_uw_NN+size_vw_NN-1]
        wT_weights = p[18+size_uw_NN+size_vw_NN:end]
        uw_NN = re_uw(uw_weights)
        vw_NN = re_vw(vw_weights)
        wT_NN = re_wT(wT_weights)
        A = - τ / H
        B = f * τ
        u = x[1:Nz]
        v = x[Nz+1:2*Nz]
        T = x[2*Nz+1:end]
        dx[1:Nz] .= A .* σ_uw ./ σ_u .* (D_cell * predict_NDE(uw_NN, x, uw_top, uw_bottom)) .+ B ./ σ_u .* (σ_v .* v .+ μ_v) #nondimensional gradient
        dx[Nz+1:2*Nz] .= A .* σ_vw ./ σ_v .* (D_cell * predict_NDE(vw_NN, x, vw_top, vw_bottom)) .- B ./ σ_v .* (σ_u .* u .+ μ_u)
        dx[2*Nz+1:end] .= A .* σ_wT ./ σ_T .* (D_cell * predict_NDE(wT_NN, x, wT_top, wT_bottom))
    end

    prob = ODEProblem(NDE_nondimensional_flux!, uvT₀, tspan_train, p_nondimensional, saveat=t_train)

    function loss_NDE_NN()
        p=[f; τ; H; μ_u; μ_v; σ_u; σ_v; σ_T; σ_uw; σ_vw; σ_wT; uw_top; uw_bottom; vw_top; vw_bottom; wT_top; wT_bottom; uw_weights; vw_weights; wT_weights]
        _sol = Array(solve(prob, opt_NDE, p=p, reltol=1f-3, sense=InterpolatingAdjoint(autojacvec=ZygoteVJP())))
        loss = Flux.mse(_sol, uvT_train)
        return loss
    end

    function cb_NDE()
        p=[f; τ; H; μ_u; μ_v; σ_u; σ_v; σ_T; σ_uw; σ_vw; σ_wT; uw_top; uw_bottom; vw_top; vw_bottom; wT_top; wT_bottom; uw_weights; vw_weights; wT_weights]
        _sol = Array(solve(prob, opt_NDE, p=p, sense=InterpolatingAdjoint(autojacvec=ZygoteVJP())))
        loss = Flux.mse(_sol, uvT_train)
        @info loss
        return _sol
    end

    Flux.train!(loss_NDE_NN, Flux.params(uw_weights, vw_weights, wT_weights), Iterators.repeated((), epochs), ADAM(0.01), cb=Flux.throttle(cb_NDE,2))

    return uw_weights, vw_weights, wT_weights    
end



train_NDE(𝒟train, uw_NN_model, vw_NN_model, wT_NN_model)