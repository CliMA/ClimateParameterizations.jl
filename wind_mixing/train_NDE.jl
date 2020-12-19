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

# Training data
train_files = ["strong_wind"]

output_gif_directory = "Output"
PATH = pwd()

𝒟train = data(train_files, scale_type=ZeroMeanUnitVarianceScaling, animate=false, animate_dir="$(output_gif_directory)/Training")

uw_NN_model = BSON.load(joinpath(PATH, "NDEs", "uw_NDE_SWNH_100.bson"))[:neural_network]
vw_NN_model = BSON.load(joinpath(PATH, "NDEs", "vw_NDE_SWNH_100.bson"))[:neural_network]
wT_NN_model = BSON.load(joinpath(PATH, "NDEs", "wT_NDE_SWNH_100.bson"))[:neural_network]

function predict_NDE(NN, x, top, bottom)
    interior = NN(x)
    return [top; interior; bottom]
end

# Set up the correct boundary conditions depending on the training data
if train_files[1] == "strong_wind_no_coriolis"
    f = 0f0
else
    f = 1f-4
end
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

if train_files[1] == "strong_wind"
    uw_bottom = Float32(uw_scaling(-1e-3))
elseif train_files[1] == "strong_wind_weak_heating"
    uw_bottom = Float32(uw_scaling(-1e-3))
elseif train_files[1] == "strong_wind_weak_cooling"
    uw_bottom = Float32(uw_scaling(-8e-4))
elseif train_files[1] == "strong_wind_no_coriolis"
    uw_bottom = Float32(uw_scaling(-2e-4))
elseif train_files[1] == "free_convection"
    uw_bottom = Float32(uw_scaling(0.))
elseif train_files[1] == "weak_wind_strong_cooling"
    uw_bottom = Float32(uw_scaling(-3e-4))
end
    
vw_top = Float32(𝒟train.vw.scaled[1,1])
vw_bottom = Float32(𝒟train.vw.scaled[end,1])
wT_top = Float32(𝒟train.wT.scaled[1,1])
if train_files[1] == "strong_wind"
    wT_bottom = Float32(wT_scaling(0.))
elseif train_files[1] == "strong_wind_weak_heating"
    wT_bottom = Float32(wT_scaling(-4e-8))
elseif train_files[1] == "strong_wind_weak_cooling"
    wT_bottom = Float32(wT_scaling(3e-8))
elseif train_files[1] == "strong_wind_no_coriolis"
    wT_bottom = Float32(wT_scaling(0.))
elseif train_files[1] == "free_convection"
    wT_bottom = Float32(wT_scaling(1.2e-7))
elseif train_files[1] == "weak_wind_strong_cooling"
    wT_bottom = Float32(wT_scaling(1e-7))
end

size_uw_NN = length(uw_weights)
size_vw_NN = length(vw_weights)
size_wT_NN = length(wT_weights)

p_nondimensional = [f; τ; H; μ_u; μ_v; σ_u; σ_v; σ_T; σ_uw; σ_vw; σ_wT; uw_top; uw_bottom; vw_top; vw_bottom; wT_top; wT_bottom; uw_weights; vw_weights; wT_weights]

# Differentiation Operator to take the vertical gradients of fluxes
D_cell = Float32.(Dᶜ(Nz, 1 / Nz))

# Coupled Neural Differential Equations
function NDE_nondimensional_flux(x, p, t)
    f, τ, H, μ_u, μ_v, σ_u, σ_v, σ_T, σ_uw, σ_vw, σ_wT, uw_top, uw_bottom, vw_top, vw_bottom, wT_top, wT_bottom = p[1:17]
    Nz = 32
    uw_weights = p[18:18 + size_uw_NN - 1]
    vw_weights = p[18 + size_uw_NN:18 + size_uw_NN + size_vw_NN - 1]
    wT_weights = p[18 + size_uw_NN + size_vw_NN:18 + size_uw_NN + size_vw_NN + size_wT_NN - 1]
    uw_NN = re_uw(uw_weights)
    vw_NN = re_vw(vw_weights)
    wT_NN = re_wT(wT_weights)
    A = - τ / H
    B = f * τ
    u = x[1:Nz]
    v = x[Nz + 1:2 * Nz]
    T = x[2 * Nz + 1:96]
    dx₁ = A .* σ_uw ./ σ_u .* D_cell * predict_NDE(uw_NN, x, uw_top, uw_bottom) .+ B ./ σ_u .* (σ_v .* v .+ μ_v)
    dx₂ = A .* σ_vw ./ σ_v .* D_cell * predict_NDE(vw_NN, x, vw_top, vw_bottom) .- B ./ σ_v .* (σ_u .* u .+ μ_u)
    dx₃ = A .* σ_wT ./ σ_T .* D_cell * predict_NDE(wT_NN, x, wT_top, wT_bottom)
    return [dx₁; dx₂; dx₃]
end

# Data Subsampling
function time_window(t, uvT, trange)
    return (Float32.(t[trange]), Float32.(uvT[:,trange]))
end

start_index = 1
end_index = 100

timesteps = start_index:5:end_index
uvT₀ = Float32.(𝒟train.uvT_scaled[:,start_index])

t_train, uvT_train = time_window(𝒟train.t, 𝒟train.uvT_scaled, timesteps)
t_train = Float32.(t_train ./ τ)
tspan_train = (t_train[1], t_train[end])

opt_NDE = Tsit5()
prob = ODEProblem(NDE_nondimensional_flux, uvT₀, tspan_train, p_nondimensional, saveat=t_train)

function loss_NDE_NN()
    p = [f; τ; H; μ_u; μ_v; σ_u; σ_v; σ_T; σ_uw; σ_vw; σ_wT; uw_top; uw_bottom; vw_top; vw_bottom; wT_top; wT_bottom; uw_weights; vw_weights; wT_weights]  
    _sol = Array(solve(prob, opt_NDE, p=p, reltol=1f-5, saveat=t_train, sensealg=InterpolatingAdjoint(autojacvec=ZygoteVJP())))
    loss = Flux.mse(_sol, uvT_train)
    return loss
end

loss_NDE_NN()

function cb_NDE()
    p = [f; τ; H; μ_u; μ_v; σ_u; σ_v; σ_T; σ_uw; σ_vw; σ_wT; uw_top; uw_bottom; vw_top; vw_bottom; wT_top; wT_bottom; uw_weights; vw_weights; wT_weights]
    _sol = Array(solve(prob, opt_NDE, p=p, reltol=1f-5, saveat=t_train, sensealg=InterpolatingAdjoint(autojacvec=ZygoteVJP())))
    loss = Flux.mse(_sol, uvT_train)
    @info loss
    return _sol
end

function save_NDE_weights()
    uw_NN_params = Dict(:weights => uw_weights)
    bson(joinpath(PATH, "Output", "uw_NDE_weights_2DaySuite_100.bson"), uw_NN_params)

    vw_NN_params = Dict(:weights => vw_weights)
    bson(joinpath(PATH, "Output", "vw_NDE_weights_2DaySuite_100.bson"), vw_NN_params)

    wT_NN_params = Dict(:weights => wT_weights)
    bson(joinpath(PATH, "Output", "wT_NDE_weights_2DaySuite_100.bson"), wT_NN_params)
end

function train_NDE(epochs)
    for i in 1:epochs
        @info "epoch $i/$epochs"
        Flux.train!(loss_NDE_NN, Flux.params(uw_weights, vw_weights, wT_weights), Iterators.repeated((), 2), ADAM(0.01), cb=Flux.throttle(cb_NDE, 5))
        if i % 5 == 0
            save_NDE_weights()
        end
    end
    save_NDE_weights()
end

# Train the Neural Differential Equations
train_NDE(2000)
