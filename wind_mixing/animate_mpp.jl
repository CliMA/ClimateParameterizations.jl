using Statistics
using Plots
using Flux
using OceanParameterizations
using Oceananigans.Grids
using BSON
using OrdinaryDiffEq, DiffEqSensitivity
using WindMixing
using JLD2
using FileIO

PATH = joinpath(pwd(), "extracted_training_output")
# PATH = "D:\\University Matters\\Massachusetts Institute of Technology\\CLiMA Project\\OceanParameterizations.jl\\training_output"


# DATA_NAME = "parameter_optimisation_8sim_windcooling_windheating_5params_BFGS_T0.5_nograd"
DATA_NAME = "parameter_optimisation_8sim_windcooling_windheating_5params_LBFGS_T0.8_grad"
# DATA_NAME = "parameter_optimisation_8sim_windcooling_windheating_5params_LBFGS_T0.8_nograd"
# DATA_NAME = "parameter_optimisation_8sim_windcooling_windheating_5params_BFGS_T0.5_grad"

DATA_PATH = joinpath(PATH, "$(DATA_NAME)_extracted.jld2")
ispath(DATA_PATH)

FILE_PATH = joinpath(pwd(), "Output", "mpp_8simnew_5params_BFGS_T0.8_nograd")

if !ispath(FILE_PATH)
    mkdir(FILE_PATH)
end


file = jldopen(DATA_PATH, "r")

train_files = file["training_info/train_files"]
train_parameters = file["training_info/parameters"]
loss_scalings = file["training_info/loss_scalings"]
mpp_parameters = file["parameters"]

𝒟train = WindMixing.data(train_files, scale_type=ZeroMeanUnitVarianceScaling, enforce_surface_fluxes=false)
close(file)

# ν₀_initial = 1f-4
# ν₋_initial = 1f-1
# ΔRi_initial = 1f-1
# Riᶜ_initial = 0.25f0
# Pr_initial = 1f0

# mpp_scalings = 1 ./ [ν₀_initial, ν₋_initial, ΔRi_initial, Riᶜ_initial, Pr_initial]

# ν₀, ν₋, ΔRi, Riᶜ, Pr = mpp_parameters ./ mpp_scalings
ν₀, ν₋, ΔRi, Riᶜ, Pr = mpp_parameters


# ν₀ = train_parameters["ν₀"]
# ν₋ = train_parameters["ν₋"]
# ΔRi = train_parameters["ΔRi"]
# Riᶜ = train_parameters["Riᶜ"]
# Pr = 1f0

N_inputs = 96
hidden_units = 400
N_outputs = 31

weights, re = Flux.destructure(Chain(Dense(N_inputs, hidden_units, relu), Dense(hidden_units, N_outputs)))

uw_NN = re(zeros(Float32, length(weights)))
vw_NN = re(zeros(Float32, length(weights)))
wT_NN = re(zeros(Float32, length(weights)))

to_run = [
    "wind_-5e-4_cooling_3e-8_new",   
    "wind_-5e-4_cooling_1e-8_new",   
    "wind_-2e-4_cooling_3e-8_new",   
    "wind_-2e-4_cooling_1e-8_new",   
    "wind_-5e-4_heating_-3e-8_new",  
    "wind_-2e-4_heating_-1e-8_new",  
    "wind_-2e-4_heating_-3e-8_new",  
    "wind_-5e-4_heating_-1e-8_new",  
  
    "wind_-3.5e-4_cooling_2e-8_new", 
    "wind_-3.5e-4_heating_-2e-8_new",
  
    "wind_-5e-4_cooling_2e-8_new",   
    "wind_-3.5e-4_cooling_3e-8_new", 
    "wind_-3.5e-4_cooling_1e-8_new", 
    "wind_-2e-4_cooling_2e-8_new",   
    "wind_-3.5e-4_heating_-3e-8_new",
    "wind_-3.5e-4_heating_-1e-8_new",
    "wind_-2e-4_heating_-2e-8_new",  
    "wind_-5e-4_heating_-2e-8_new",  
  ]

for test_file in to_run
    @info "running $test_file"
    test_files = [test_file]
    𝒟test = WindMixing.data(test_files, scale_type=ZeroMeanUnitVarianceScaling, enforce_surface_fluxes=false)
    trange = 1:1:1153
    plot_data = NDE_profile(uw_NN, vw_NN, wT_NN, 𝒟test, 𝒟train, trange,
                            modified_pacanowski_philander=true, 
                            ν₀=ν₀, ν₋=ν₋, ΔRi=ΔRi, Riᶜ=Riᶜ, Pr=Pr,
                            convective_adjustment=false,
                            smooth_NN=false, smooth_Ri=false,
                            zero_weights=true,
                            loss_scalings=loss_scalings)

    animation_type = "Pre-Training"
    n_trainings = length(train_files)
    training_types = "Modified Pacanowski-Philander"
    VIDEO_NAME = "$(test_file)_mpp"
    animate_profiles_fluxes_comparison(plot_data, plot_data, plot_data, joinpath(FILE_PATH, VIDEO_NAME), fps=30, 
                                                    animation_type=animation_type, n_trainings=n_trainings, training_types=training_types)
end
