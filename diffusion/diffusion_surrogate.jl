using DifferentialEquations
using DiffEqFlux
using Flux
using Gen
using Plots
using ClimateSurrogates

# For quick headless plotting without warnings.
# See: https://github.com/jheinen/GR.jl/issues/278
ENV["GKSwstype"] = "100"

#####
##### Generating solutions and training data
#####

function diffusion!(∂u∂t, u, p, t)
    N, Δx, κ = p.N, p.Δx, p.κ
    @inbounds begin
        ∂u∂t[1] = κ * (u[N] -2u[1] + u[2]) / Δx
        for i in 2:N-1
            ∂u∂t[i] = κ * (u[i-1] -2u[i] + u[i+1]) / Δx
        end
        ∂u∂t[N] = κ * (u[N-1] -2u[N] + u[1]) / Δx
    end
    return nothing
end

"""
    solve_diffusion_equation(; u₀, N, L, κ, T, Nt)

Solve a 1D diffusion equation with initial condition given by `u₀(x)` on a domain -L/2 <= x <= L/2 with diffusivity `κ` using `N` grid points for time 0 <= t <= `T`. A solution with `Nt` outputs will be returned.
"""
function solve_diffusion_equation(; u₀, N, L, κ, T, Nt)
    Δx = L / N
    x = range(-L/2, L/2, length=N)
    ic = u₀.(x)

    tspan = (0.0, T)
    Δt = (tspan[2] - tspan[1]) / Nt
    t = range(tspan[1], tspan[2], length=Nt)

    params = (N=N, Δx=Δx, κ=κ, x=x)
    prob = ODEProblem(diffusion!, ic, tspan, params)
    solution = solve(prob, Tsit5(), saveat=t)

    return solution
end

function generate_training_data(sol)
    N, Nt = size(sol)

    uₙ    = zeros(N, Nt-1)
    uₙ₊₁  = zeros(N, Nt-1)

    for i in 1:Nt-1
           uₙ[:, i] .=  sol.u[i]
         uₙ₊₁[:, i] .=  sol.u[i+1]
    end

    training_data = [(uₙ[:, i], uₙ₊₁[:, i]) for i in 1:Nt-1]

    return training_data
end

function generate_solutions(training_functions, testing_functions; N, L, κ, T, Nt, animate=false)
    # Generate truth solutions for training and testing
    solutions = Dict()
    training_solutions = Dict()
    testing_solutions = Dict()
    training_data = []
    testing_data = []

    for u₀ in (training_functions..., testing_functions...)
        sol = solve_diffusion_equation(u₀=u₀, N=N, L=L, κ=κ, T=T, Nt=Nt)
        solutions[function_name(u₀)] = sol

        if u₀ in training_functions
            training_solutions[function_name(u₀)] = sol
            append!(training_data, generate_training_data(sol))
        elseif u₀ in testing_functions
            testing_solutions[function_name(u₀)] = sol
            append!(testing_data, generate_training_data(sol))
        end

        if animate
            fname = "diffusing_$(function_name(u₀)).mp4"
            animate_solution(sol, filename=fname)
        end
    end

    return solutions, training_solutions, testing_solutions, training_data, testing_data
end

function animate_solution(sol; filename, fps=15)
    Nt = length(sol)
    x = sol.prob.p.x

    anim = @animate for n=1:Nt
        plot(x, sol.u[n], linewidth=2, ylim=(0, 2), label="", show=false)
    end

    mp4(anim, filename, fps=fps)
end

#####
##### Neural differential equation
#####

function generate_neural_pde_architecture(N)
    # dudt_NN = FastChain(FastDense(N, N))

    # dudt_NN = FastChain(FastDense(N, 100, tanh),
    #                     FastDense(100, N))

    # Conservation matrix
    C = Matrix{Float64}(I, N, N)
    C[end, 1:end-1] .= -1
    C[end, end] = 0

    dudt_NN = Chain(Dense(N, N), u -> C*u)

    return dudt_NN
end

function train_diffusion_neural_pde(training_data, NN, optimizers)
    # Set up neural differential equation
    tspan_npde = (0.0, Δt)
    diffusion_npde = NeuralODE(NN, tspan_npde, Tsit5(), reltol=1e-4, saveat=[Δt])

    loss_function(θ, uₙ, uₙ₊₁) = Flux.mse(uₙ₊₁, diffusion_npde(uₙ, θ)) ./ (sum(abs2, uₙ₊₁) + 1e-6)
    training_loss(θ, data) = sum([loss_function(θ, data[i]...) for i in 1:length(data)])

    function cb(θ, args...)
        println("train_loss = $(training_loss(θ, training_data))")
        return false
    end

    # Train!
    for opt in optimizers
        @info "Training with optimizer: $(typeof(opt))..."
        if opt isa Optim.AbstractOptimizer
            full_loss(θ) = training_loss(θ, training_data)
            res = DiffEqFlux.sciml_train(full_loss, diffusion_npde.p, opt, cb=cb, maxiters=100)
            display(res)
            diffusion_npde.p .= res.minimizer
        else
            epochs = 10
            for e in 1:epochs
                @info "Training with optimizer: $(typeof(opt)) epoch $e..."
                res = DiffEqFlux.sciml_train(loss_function, diffusion_npde.p, opt, training_data, cb=cb)
                diffusion_npde.p .= res.minimizer
            end
        end
    end

    return diffusion_npde
end

function test_diffusion_neural_pde(npde, solutions)
    for (name, sol) in solutions
        u_NN = animate_neural_pde_test(sol, npde, filename="NPDE_test_$name.mp4")
        plot_conservation(u_NN, sol.t, filename="NPDE_conservation_$name.png")
    end
    return nothing
end

function animate_neural_pde_test(sol, nde; filename, fps=15)
    N, Nt = size(sol)
    x = sol.prob.p.x

    u_NN = zeros(N, Nt)
    u_NN[:, 1] .= sol.u[1]

    for n in 2:Nt
        sol_NN = nde(u_NN[:, n-1])
        u_NN[:, n] .= sol_NN.u[1]
    end

    anim = @animate for n=1:Nt
        plot(x, sol.u[n],    linewidth=2, ylim=(0, 2), label="Data", show=false)
        plot!(x, u_NN[:, n], linewidth=2, ylim=(0, 2), label="Neural PDE", show=false)
    end

    mp4(anim, filename, fps=fps)

    return u_NN
end

#####
##### Gaussian process
#####

@gen function generate_gp_kernel()
    l ~ gamma(1, 2)
    σ² ~ gamma(1, 2)
    kernel = SquaredExponential(l, σ²)
    return kernel
end

@gen function train_diffusion_gp(training_data)
    kernel ~ generate_gp_kernel()

    # Split data such that y = GP(x)
    x_train = [data[1] for data in training_data]
    y_train = [data[2] for data in training_data]

    return GaussianProcess(x_train, y_train, kernel)
end

@gen function predict_diffusion_gp(training_data, u₀, Nt)
    gp ~ train_diffusion_gp(training_data)

    N = length(u₀)
    u_GP = zeros(N, Nt)
    u_GP[:, 1] .= u₀

    for n in 2:Nt
        u_GP[:, n] .= predict(gp, [u_GP[:, n-1]])
        for i in 1:N
            {(:u, n, i)} ~ normal(u_GP[i, n], 0.01)
        end
    end

    return u_GP
end

function infer_gp_hyperparameters(training_data, sol; iters)
    u₀ = sol.u[1]
    N, Nt = size(sol)

    observations = Gen.choicemap()
    for n in 2:Nt, i in 1:N
        observations[(:u, n, i)] = sol.u[n][i]
    end

    trace, _ = Gen.generate(predict_diffusion_gp, (training_data, u₀, Nt), observations)

    gp_hyperparameters = select(:gp => :kernel => :l, :gp => :kernel => :σ²)
    for _ in 1:iters
        trace, _ = metropolis_hastings(trace, gp_hyperparameters)
    end

    return trace
end

function test_diffusion_gp(gp, solutions)
    for (name, sol) in solutions
        u_GP = animate_gp_test(sol, gp, filename="GP_test_$name.mp4")
        plot_conservation(u_GP, sol.t, filename="GP_conservation_$name.png")
    end
    return nothing
end

function animate_gp_test(sol, gp; filename, fps=15)
    N, Nt = size(sol)
    x = sol.prob.p.x

    u_GP = zeros(N, Nt)
    u_GP[:, 1] .= sol.u[1]

    for n in 2:Nt
        u_GP[:, n] .= predict(gp, [u_GP[:, n-1]])
    end

    anim = @animate for n=1:Nt
        plot(x, sol.u[n],    linewidth=2, ylim=(0, 2), label="Data", show=false)
        plot!(x, u_GP[:, n], linewidth=2, ylim=(0, 2), label="GP", show=false)
    end

    mp4(anim, filename, fps=fps)

    return u_GP
end

#####
##### General testing
#####

function plot_conservation(u, t; filename)
    N, Nt = size(u)
    Σu₀ = sum(u[:, 1])
    Σu = [sum(u[:, n]) for n in 1:Nt]

    p = plot(t, Σu .- Σu₀, linewidth=2, title="Conservation", label="")

    @info "Saving $filename..."
    savefig(p, filename)
end
