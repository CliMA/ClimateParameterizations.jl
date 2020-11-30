using ClimateParameterizations
using Flux, OceanTurb, DifferentialEquations, Plots

output_gif_directory = "Output1"

train_files = ["strong_wind", "free_convection"]
test_file = "strong_wind"

𝒟train = ClimateParameterizations.Data.data(train_files,
                                        scale_type=ZeroMeanUnitVarianceScaling,
                                        animate=false,
                                        animate_dir="$(output_gif_directory)/Training")
𝒟test = ClimateParameterizations.Data.data(test_file,
                                        override_scalings=𝒟train.scalings, # use the scalings from the training data
                                        animate=false,
                                        animate_dir="$(output_gif_directory)/Testing")

## Neural Networks

# trained NN models
uw_NN_model = nn_model(𝒱 = 𝒟train.uw,
                    model = Chain(Dense(96,96, relu), Dense(96,96, relu), Dense(96,33)),
                    optimizers = [ADAM(), ADAM(), ADAM(), ADAM(), Descent(), Descent(), Descent(), Descent(), Descent()],
                   )

vw_NN_model = nn_model(𝒱 = 𝒟train.vw,
                    model = Chain(Dense(96,96, relu), Dense(96,96, relu), Dense(96,33)),
                    optimizers = [ADAM(), ADAM(), ADAM(), ADAM(), Descent(), Descent(), Descent(), Descent(), Descent()],
                   )

wT_NN_model = nn_model(𝒱 = 𝒟train.wT,
                    model = Chain(Dense(96,96, relu), Dense(96,96, relu), Dense(96,33)),
                    optimizers = [ADAM(), ADAM(), ADAM(), ADAM(), ADAM(), ADAM(), ADAM(), ADAM(), Descent(), Descent(), Descent(), Descent(), Descent(), Descent()],
                   )

uw_NN = predict(𝒟test.uw, uw_NN_model)
vw_NN = predict(𝒟test.vw, vw_NN_model)
wT_NN = predict(𝒟test.wT, wT_NN_model)

# Compare NN predictions to truth
animate_gif(uw_NN, 𝒟test.uw.z, 𝒟test.t, "uw", ["NN(u,v,T)", "truth"], "uw_NN", dir=output_gif_directory)
animate_gif(vw_NN, 𝒟test.vw.z, 𝒟test.t, "vw", ["NN(u,v,T)", "truth"], "vw_NN", dir=output_gif_directory)
animate_gif(wT_NN, 𝒟test.wT.z, 𝒟test.t, "wT", ["NN(u,v,T)", "truth"], "wT_NN", dir=output_gif_directory)


## Gaussian Process Regression

# trained GP models
logγ_range=-2.0:0.5:2.0
# uw_GP_model = ClimateParameterizations.GaussianProcess.gp_model(𝒟train.uw, logγ_range=logγ_range, kernel=get_kernel(1, 0.3, 0.0, euclidean_distance))
uw_GP_model = ClimateParameterizations.GaussianProcess.gp_model(𝒟train.uw, logγ_range=logγ_range)
vw_GP_model = ClimateParameterizations.GaussianProcess.gp_model(𝒟train.vw, logγ_range=logγ_range)
wT_GP_model = ClimateParameterizations.GaussianProcess.gp_model(𝒟train.wT, logγ_range=logγ_range)

# GP predictions on test data
uw_GP = predict(𝒟test.uw, uw_GP_model)
vw_GP = predict(𝒟test.vw, vw_GP_model)
wT_GP = predict(𝒟test.wT, wT_GP_model)

mse(x::Tuple{Array{Float64,2}, Array{Float64,2}}) = Flux.mse(x[1], x[2])
mse(uw_GP)
mse(vw_GP)
mse(wT_GP)

# Compare GP predictions to truth
animate_gif(uw_GP, 𝒟test.uw.z, 𝒟test.t, "uw", ["GP(u,v,T)", "truth"], "uw_GP", dir=output_gif_directory)
animate_gif(vw_GP, 𝒟test.vw.z, 𝒟test.t, "vw", ["GP(u,v,T)", "truth"], "vw_GP", dir=output_gif_directory)
animate_gif(wT_GP, 𝒟test.wT.z, 𝒟test.t, "wT", ["GP(u,v,T)", "truth"], "wT_GP", dir=output_gif_directory)

## KPP Parameterization (no training)

Δt = 𝒟test.t[2] - 𝒟test.t[1]
les = read_les_output(test_file)
parameters = KPP.Parameters() # default parameters
predictions = closure_free_convection_kpp_full_evolution(parameters, 33, Δt, les)
T_KPP = (predictions, 𝒟test.T_coarse)
mse(T_KPP)
animate_gif(T_KPP, 𝒟test.uw.z, 𝒟test.t, "T (C)", ["KPP(T)", "truth"], "T_KPP", dir=output_gif_directory)

## TKE Parameterization (no training; use default parameters)

Δt = 𝒟test.t[2] - 𝒟test.t[1]
les = read_les_output(test_file)
parameters = TKEMassFlux.TKEParameters() # default parameters
predictions = closure_free_convection_kpp_full_evolution(problem.parameters, 33, Δt, les)
T_KPP = (predictions, 𝒟test.T_coarse)
mse(T_KPP)
animate_gif(T_KPP, 𝒟test.uw.z, 𝒟test.t, "T (C)", ["TKE(T)", "truth"], "T_TKE", dir=output_gif_directory)

## Solving the PDEs using the predictions from NN or GP models

# function NDE_prediction(𝒟test, uw_model, vw_model, wT_model)
    z = 𝒟test.z
    t = 𝒟test.t
    tspan_train = (0.0, t[100])
    uvT₀ = 𝒟test.uvT_scaled[:,1]

    # central derivative as gradient approximator, periodic boundary conditions
    function central_difference(input, z)
        Δ = z[2] - z[1]
        output = similar(input)
        vals = @view output[2:length(output)-1]
        vals .= (@view(input[3:end]) .- @view(input[1:end-2])) ./ (2Δ)
        # output[1] = (input[2] - input[end]) / (2Δ)
        # output[end] = (input[1] - input[end-1])/(2Δ)
        output[1] = 0
        output[end] = 0
        return output
    end

    # interpolation from face centered values to cell centered values
    function face_to_cell(input)
        output = similar(input, length(input)-1)
        output .= (@view(input[1:end-1]) .+ @view(input[2:end]) ) ./ 2
        return output
    end

    # splicing data to train the NN
    function time_window(t, uvT, stopindex)
        if stopindex < length(t)
            return (t[1:stopindex], uvT[:,1:stopindex])
        else
            @info "stop index larger than length of t"
        end
    end

    function NDE!(dx, x, p, t)
        f = p[1]
        Nz = Int(p[2])
        u = x[1:Nz]
        v = x[Nz+1:2*Nz]
        T = x[2*Nz+1:end]
        dx[1:Nz] .= -1 .* central_difference(uw_model(x), z) .+ f .* v
        dx[Nz+1:2*Nz] .= -1 .* central_difference(vw_model(x), z) .- f .* u
        dx[2*Nz+1:end] .= -1 .* central_difference(face_to_cell(wT_model(x)), z)
    end

    t_train, uvT_train = time_window(t, 𝒟test.uvT_scaled, 2)

    prob = ODEProblem(NDE!, uvT₀, (t_train[1],t_train[end]), [10e-4, 32], saveat=t_train)

    sol = solve(prob)
    plot(sol[:,end][33:64], z)

    loss_NDE(x, y) = Flux.mse(x, y)
    cb() = @info Flux.mse(Array(solve(prob)), uvT_train)

    params = Flux.params([uw_model, vw_model, wT_model])
    data = zip(Array(solve(prob)), uvT_train)
    Flux.train!(loss_NDE, params, data, ADAM(), cb = Flux.throttle(cb, 2))

# end
