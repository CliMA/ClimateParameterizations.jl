module ClimateParameterizations

if VERSION < v"1.5"
    error("ClimateParameterizations.jl requires Julia v1.5 or newer.")
end

export
    # Utils
    coarse_grain, Dᶠ, Dᶜ,
    ZeroMeanUnitVarianceScaling, MinMaxScaling, scale, unscale,
    GaussianProcess, predict, uncertainty, SquaredExponential,

    # Ocean convection
    nc_constant,
    FreeConvectionTrainingDataInput, rescale,
    FreeConvectionNDE, ConvectiveAdjustmentNDE, FreeConvectionNDEParameters, initial_condition,
    solve_free_convection_nde, solve_convective_adjustment_nde, free_convection_solution,
    animate_variable, convection_training_data, animate_learned_heat_flux

using LinearAlgebra
using Printf
using Statistics
using Logging

using DifferentialEquations
using Flux
using NCDatasets
using Plots
using Oceananigans.Utils

using Oceananigans: OceananigansLogger
using Oceananigans.Grids: Cell, Face
using DiffEqSensitivity: InterpolatingAdjoint, ZygoteVJP

import Base.inv

include("differentiation_operators.jl")
# include("gaussian_process.jl")

include("ocean_convection.jl")

function __init__()
    Logging.global_logger(OceananigansLogger())
end

export
    # Data / profile_data.jl
    data,
    VData,
    ProfileData,

    # Data / les/read_les_output.jl
    read_les_output,

    # Data / kpp/run.jl
    closure_free_convection_kpp_full_evolution,

    # Data / tke/run.jl
    closure_free_convection_tke_full_evolution,

    # NeuralNetwork / NeuralNetwork.jl
    nn_model,

    # GaussianProcess / gp.jl
    gp_model,

    # GaussianProcess / kernels.jl
    Kernel,
    get_kernel,
    kernel_function,

    # GaussianProcess / distances.jl
    euclidean_distance,
    derivative_distance,
    antiderivative_distance,

    # Main
    mean_square_error,
    predict,

    # Data / animate_gif.jl
    animate_gif

# modules
using Plots,
      JLD2,
      NetCDF,
      Statistics,
      # LinearAlgebra,
      BenchmarkTools,
      Optim,
      Statistics,
      Flux,
      DiffEqFlux,
      Oceananigans.Grids

# OceanTurb for KPP
using OceanTurb
export KPP, TKEMassFlux

# submodules
include("data/Data.jl")
include("gpr/GaussianProcess.jl")
include("nn/NeuralNetwork.jl")
include("main/Main.jl")

using .Data
using .GaussianProcess
using .NeuralNetwork
using .Main

end # module
