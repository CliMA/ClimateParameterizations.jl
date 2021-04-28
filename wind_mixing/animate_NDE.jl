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
# DATA_PATH = joinpath(PATH, "extracted_training_output", "NDE_training_modified_pacanowski_philander_1sim_-1e-3_2_extracted.jld2")
DATA_PATH = joinpath(PATH, 
                    "NDE_training_modified_pacanowski_philander_1sim_-1e-3_diffusivity_1e-1_Ri_1e-1_zeroweights_gradient_smallNN_scale_5e-3_2_extracted.jld2")

                    # FILE_PATH = "D:\\University Matters\\Massachusetts Institute of Technology\\CLiMA Project\\OceanParameterizations.jl\\training_output"
FILE_PATH = joinpath(PATH, "Output")
VIDEO_NAME = "u_v_T_pacanowski_philander_diffusivity_1e-1_Ri_1e-1_zero_weights_smallNN_gradient_scale_5e-3_comparison"
# VIDEO_NAME = "test_flux"
# SIMULATION_NAME = "NN Smoothing Wind-Mixing, Testing Data"
SIMULATION_NAME = "Modified Pacanowski Philander"

file = jldopen(DATA_PATH, "r")

losses = file["losses"]

minimum(losses)

train_files = file["training_info/train_files"]
train_parameters = file["training_info/parameters"]

Plots.plot(1:1:length(losses), losses, yscale=:log10)
Plots.xlabel!("Iteration")
Plots.ylabel!("Loss mse")
# savefig(joinpath(PATH, "Output", "NDE_training_modified_pacanowski_philander_1sim_-1e-3_smaller_learning_rate_loss.pdf"))

𝒟train = WindMixing.data(train_files, scale_type=ZeroMeanUnitVarianceScaling, enforce_surface_fluxes=true)

test_files = ["-1e-3"]
𝒟test = WindMixing.data(test_files, scale_type=ZeroMeanUnitVarianceScaling, enforce_surface_fluxes=true)
uw_NN = file["neural_network/uw"]
vw_NN = file["neural_network/vw"]
wT_NN = file["neural_network/wT"]

# NN = Chain(Dense(96, 400, relu), Dense(400,31))

# [NN(uvT[:,100]) NN(ones(96))]

Flux.destructure(uw_NN)[1][end-31:end]

Flux.destructure(uw_NN)[1][1:end-31] .== 0

uvT = 𝒟train.uvT_scaled

[uw_NN(uvT[:,100]) uw_NN(zeros(96)) uw_NN(rand(96)) Flux.destructure(uw_NN)[1][end-30:end]]

NN_PATH = joinpath(PATH, "NDE_training_modified_pacanowski_philander_1sim_-1e-3_diffusivity_1e-1_Ri_1e-1_zeroweights_gradient_smallNN_scale_5e-3.jld2")

NN_data = jldopen(NN_PATH, "r")

Flux.destructure(NN_data["training_data/neural_network/uw/1/500"])[1][end-50:end]

# N_inputs = 96
# hidden_units = 400
# N_outputs = 33

# weights, re = Flux.destructure(Chain(Dense(N_inputs, hidden_units, relu), Dense(hidden_units, hidden_units, relu), Dense(hidden_units, hidden_units, relu), Dense(hidden_units, N_outputs)))

# uw_NN = re(zeros(Float32, size(weights)))
# vw_NN = re(zeros(Float32, size(weights)))
# wT_NN = re(zeros(Float32, size(weights)))

# uw_weights, re_uw = Flux.destructure(uw_NN)
# vw_weights, re_vw = Flux.destructure(vw_NN)
# wT_weights, re_wT = Flux.destructure(wT_NN)

# uw_weights .= 0f0

# uw_NN = re_uw(uw_weights)
# vw_NN = re_vw(uw_weights)
# wT_NN = re_wT(uw_weights)

trange = 1:1:1153
plot_data = NDE_profile(uw_NN, vw_NN, wT_NN, 𝒟test, 𝒟train, trange,
                        # modified_pacanowski_philander=true, 
                        modified_pacanowski_philander=train_parameters["modified_pacanowski_philander"], 
                        # ν₀=train_parameters["ν₀"], ν₋=train_parameters["ν₋"], ΔRi=1f-1, 
                        ν₀=train_parameters["ν₀"], ν₋=train_parameters["ν₋"], ΔRi=train_parameters["ΔRi"], 
                        Riᶜ=train_parameters["Riᶜ"], convective_adjustment=train_parameters["convective_adjustment"],
                        # Riᶜ=train_parameters["Riᶜ"], convective_adjustment=true,
                        # smooth_NN=false, smooth_Ri=train_parameters["smooth_Ri"],
                        smooth_NN=train_parameters["smooth_NN"], smooth_Ri=train_parameters["smooth_Ri"],
                        zero_weights=train_parameters["zero_weights"])
                        # zero_weights=true)
plot_data["test_Ri_NN_only"]


WindMixing.animate_profiles_fluxes(plot_data, joinpath(PATH, VIDEO_NAME), dimensionless=false, SIMULATION_NAME=SIMULATION_NAME)

WindMixing.animate_profiles_fluxes_comparison(plot_data, joinpath(PATH, VIDEO_NAME), dimensionless=false, SIMULATION_NAME=SIMULATION_NAME)

# VIDEO_NAME = "u_v_T_modified_pacanowski_philander_1sim_-1e-3_test2"


# keys(plot_data)

# plot_data["truth_T"][:,1]

# uvT_truth = [plot_data["truth_u"]; plot_data["truth_v"]; plot_data["truth_T"]]
# Ris = local_richardson(uvT_truth, 𝒟test, unscale=true)

# animate_local_richardson_profile(uvT_truth, 𝒟test, joinpath(FILE_PATH, "Ris_convective_adjustment_1sim_-1e-3_2_test"), unscale=true)

# plot(Ris[:,3], plot_data["depth_flux"])
# xlabel!("Ri")
# ylabel!("z")

# animate_profile_flux(plot_data, "u", "uw", joinpath(FILE_PATH, "u_uw_modified_pacanowski_philander_1sim_-1e-3_test"), gif=true, dimensionless=false)
# animate_profile_flux(plot_data, "v", "vw", joinpath(FILE_PATH, "v_vw_modified_pacanowski_philander_1sim_-1e-3_test"), gif=true, dimensionless=false)
# animate_profile_flux(plot_data, "T", "wT", joinpath(FILE_PATH, "w_wT_modified_pacanowski_philander_1sim_-1e-3_test"), gif=true, dimensionless=false)

# animate_profiles(plot_data, joinpath(FILE_PATH, VIDEO_NAME), dimensionless=false)

# animate_profile(plot_data, "u", "uw", joinpath(FILE_PATH, "u_uw_convective_adjustment_viscosity_empty"), gif=true)
# animate_profile(plot_data, "v", "vw", joinpath(FILE_PATH, "v_vw_convective_adjustment_viscosity_empty"), gif=true)
# animate_profile(plot_data, "T", "wT", joinpath(FILE_PATH, "w_wT_convective_adjustment_viscosity_empty"), gif=true)

# animate_flux(plot_data, "uw", joinpath(FILE_PATH, "uw_test"))
# animate_flux(plot_data, "vw", joinpath(FILE_PATH, "vw_test"))
# animate_flux(plot_data, "wT", joinpath(FILE_PATH, "wT_test"))
