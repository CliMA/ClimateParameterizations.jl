using OceanParameterizations
using WindMixing
using Flux
using OrdinaryDiffEq
using Plots


x_lims = Dict(
    "u" => (-2.0, 3.0),
    "v" => (-1.0, 2.0),
    "uw" => (-10,0),
    "vw" => (-4,4.5),
    "wT" => (-1.5,0.7),
    "T" => (-2.0,2.0)
)

f = Dict(
    "u" => 𝒟 -> 𝒟.u.coarse,
    "v" => 𝒟 -> 𝒟.v.coarse,
    "uw" => 𝒟 -> 𝒟.uw.coarse,
    "vw" => 𝒟 -> 𝒟.vw.coarse,
    "wT" => 𝒟 -> 𝒟.wT.coarse,
    "T"  => 𝒟 -> 𝒟.T.coarse
)

zs = Dict(
    "u" => 𝒟 -> 𝒟.u.z,
    "v" => 𝒟 -> 𝒟.v.z,
    "uw" => 𝒟 -> 𝒟.uw.z,
    "vw" => 𝒟 -> 𝒟.vw.z,
    "wT" => 𝒟 -> 𝒟.wT.z,
    "T"  => 𝒟 -> 𝒟.T.z
)

scaling_factor = Dict(
    "uw" => 1e4,
    "vw" => 1e4,
    "wT" => 1e4,
    "u" => 1,
    "v" => 1,
    "T" => 1
)

x_labels = Dict(
    "u" => "U (m/s)",
    "v" => "V (m/s)",
    "uw" => "U'W' x 10⁴ (m²/s²)",
    "vw" => "V'W' x 10⁴ (m²/s²)",
    "wT" => "W'T' x 10⁴ (C⋅m/s)",
    "T" => "T (C)"
)

titles = Dict(
    "uw" => "Zonal momentum flux, U'W'",
    "vw" => "Meridional momentum flux, V'W'",
    "wT" => "Temperature flux, W'T'",
    "u" => "Zonal momentum (m/s)",
    "v" => "Meridional momentum (m/s)",
    "T" => "Temperature, T",
)

function save_frame_n(n, xs, name, 𝒟, test_file; filename=name, legend_labels=["" for i in 1:length(xs)], directory="Output")
    filepath = pwd() * "/" * directory * "/"
    mkpath(filepath)

    fig = plot(xlim=x_lims[name], legend=:bottom, size=(400,400), xlabel=x_labels[name], ylabel="Depth (m)")
    # title=file_labels[test_file]*", $(round(𝒟.t[n]/86400, digits=1)) days",
    for i in reverse(1:length(xs))
        plot!(fig, xs[i][:,n].*scaling_factor[name], zs[name](𝒟), label=legend_labels[i], linewidth=4, la=0.5, palette=:Set1_3)
    end

    savefig(fig, pwd() * "/$(directory)/$(filename).pdf")
end

reconstruct_fluxes = false
println("Reconstruct fluxes? $(reconstruct_fluxes)")

enforce_surface_fluxes = true
println("Enforce surface fluxes? $(enforce_surface_fluxes)")

subsample_frequency = 1
println("Subsample frequency for training... $(subsample_frequency)")

file_labels = Dict(
    "free_convection" => "Free convection",
    "strong_wind" => "Strong wind",
    "strong_wind_no_coriolis" => "Strong wind, no rotation",
    "weak_wind_strong_cooling" => "Weak wind, strong cooling",
    "strong_wind_weak_cooling" => "Strong wind, weak cooling",
    "strong_wind_weak_heating" => "Strong wind, weak heating"
)

## Pick training and test simulations

train_file = "strong_wind"
test_file = "strong_wind_weak_cooling"

𝒟train = WindMixing.data(train_file,
                    scale_type=ZeroMeanUnitVarianceScaling,
                    reconstruct_fluxes=reconstruct_fluxes,
                    subsample_frequency=subsample_frequency,
                    enforce_surface_fluxes=enforce_surface_fluxes)
𝒟test = WindMixing.data(test_file,
                    override_scalings=𝒟train.scalings, # use the scalings from the training data
                    reconstruct_fluxes=reconstruct_fluxes,
                    subsample_frequency=subsample_frequency,
                    enforce_surface_fluxes=enforce_surface_fluxes)
les = read_les_output(test_file)

output_gif_directory="train_SW_test_SW_WC/subsample_$(subsample_frequency)/reconstruct_$(reconstruct_fluxes)/enforce_surface_fluxes_$(enforce_surface_fluxes)"
directory = pwd() * "/$(output_gif_directory)/"
mkpath(directory)
file = directory*"_output.txt"
touch(file)
o = open(file, "w")

write(o, "= = = = = = = = = = = = = = = = = = = = = = = = \n")
write(o, "Test file: $(test_file) \n")
write(o, "Output will be written to: $(output_gif_directory) \n")

## Gaussian Process Regression

# A. Find the kernel that minimizes the prediction error on the training data
# * Sweeps over length-scale hyperparameter value in logγ_range
# * Sweeps over covariance functions
# logγ_range=-1.0:0.5:1.0 # sweep over length-scale hyperparameter
# uncomment the next three lines to try this but just for testing the GPR use the basic get_kernel stuff below
# uw_kernel = best_kernel(𝒟train.uw, logγ_range=logγ_range)
# vw_kernel = best_kernel(𝒟train.vw, logγ_range=logγ_range)
# wT_kernel = best_kernel(𝒟train.wT, logγ_range=logγ_range)

# OR set the kernel manually here (to save a bunch of time):
# Result of the hyperparameter search - optimize_GP_kernels.jl
if reconstruct_fluxes
    uw_kernel = get_kernel(2,0.4,0.0,euclidean_distance)
    vw_kernel = get_kernel(2,0.5,0.0,euclidean_distance)
    wT_kernel = get_kernel(2,1.3,0.0,euclidean_distance)
else
    uw_kernel = get_kernel(2,0.4,0.0,euclidean_distance)
    vw_kernel = get_kernel(2,0.4,0.0,euclidean_distance)
    wT_kernel = get_kernel(2,1.2,0.0,euclidean_distance)
end

# Report the kernels and their properties
write(o, "Kernel for u'w'..... $(uw_kernel) \n")
write(o, "Kernel for v'w'..... $(vw_kernel) \n")
write(o, "Kernel for w'T'..... $(wT_kernel) \n")

# Trained GP models
uw_GP_model = gp_model(𝒟train.uw, uw_kernel)
vw_GP_model = gp_model(𝒟train.vw, vw_kernel)
wT_GP_model = gp_model(𝒟train.wT, wT_kernel)

# GP predictions on test data
uw_GP = predict(𝒟test.uw, uw_GP_model; scaled=true)
vw_GP = predict(𝒟test.vw, vw_GP_model; scaled=true)
wT_GP = predict(𝒟test.wT, wT_GP_model; scaled=true)

# Report GP prediction error on the fluxes
write(o, "GP prediction error on u'w'..... $(mse(uw_GP)) \n")
write(o, "GP prediction error on v'w'..... $(mse(vw_GP)) \n")
write(o, "GP prediction error on w'T'..... $(mse(wT_GP)) \n")

# Compare GP predictions to truth
myanimate(xs, name) = animate_prediction(xs, name, 𝒟test, test_file;
                        legend_labels=["GP(u,v,T)","Truth"], directory=output_gif_directory)
myanimate(uw_GP, "uw")
myanimate(vw_GP, "vw")
myanimate(wT_GP, "wT")

t  = 𝒟test.t
Nz = 32
f  = les.f⁰
H  = Float32(abs(𝒟test.uw.z[end] - 𝒟test.uw.z[1]))
τ  = Float32(abs(t[:,1][end] - t[:,1][1]))
u_scaling = 𝒟test.scalings["u"]
v_scaling = 𝒟test.scalings["v"]
T_scaling = 𝒟test.scalings["T"]
uw_scaling = 𝒟test.scalings["uw"]
vw_scaling = 𝒟test.scalings["vw"]
wT_scaling = 𝒟test.scalings["wT"]

get_μ_σ(name) = (𝒟test.scalings[name].μ, 𝒟test.scalings[name].σ)
μ_u, σ_u = get_μ_σ("u")
μ_v, σ_v = get_μ_σ("v")
μ_T, σ_T = get_μ_σ("T")
μ_uw, σ_uw = get_μ_σ("uw")
μ_vw, σ_vw = get_μ_σ("vw")
μ_wT, σ_wT = get_μ_σ("wT")
D_cell = Float32.(Dᶜ(Nz, 1/Nz))

top_bottom(x) = (Float32(x[1,1]), Float32(x[end,1]))
uw_top, uw_bottom = top_bottom(𝒟test.uw.scaled)
vw_top, vw_bottom = top_bottom(𝒟test.vw.scaled)
wT_top, wT_bottom = top_bottom(𝒟test.wT.scaled)

# enforce surface fluxes in the predictions
function predict_and_enforce_fluxes(model, x, top, bottom)
    return [top; model(x); bottom]
end

A = - τ / H
B = f * τ

function NDE_nondimensional_flux(x, p, t)
    u = x[1:Nz]
    v = x[Nz+1:2*Nz]
    T = x[2*Nz+1:96]
    dx₁ = A .* σ_uw ./ σ_u .* D_cell * uw_GP_model(x) .+ B ./ σ_u .* (σ_v .* v .+ μ_v) #nondimensional gradient
    dx₂ = A .* σ_vw ./ σ_v .* D_cell * vw_GP_model(x) .- B ./ σ_v .* (σ_u .* u .+ μ_u)
    dx₃ = A .* σ_wT ./ σ_T .* D_cell * wT_GP_model(x)
    return [dx₁; dx₂; dx₃]
end

function time_window(t, uvT, trange)
    return (Float32.(t[trange]), Float32.(uvT[:,trange]))
end

timesteps = 1:1:length(t) #1:5:100
uvT₀ = Float32.(𝒟test.uvT_scaled[:,1])

t_train, uvT_train = time_window(t, 𝒟test.uvT_scaled, timesteps)
t_train = Float32.(t_train ./ τ)

prob = ODEProblem(NDE_nondimensional_flux, uvT₀, (t_train[1], t_train[end]), saveat=t_train)
sol = solve(prob, Tsit5())

split_array(uvT) = (uvT[1:Nz,:], uvT[Nz+1:2*Nz,:], uvT[2*Nz+1:end,:])
u_pred, v_pred, T_pred = split_array(sol)

u_pair = (u_pred, 𝒟test.u.scaled)
v_pair = (v_pred, 𝒟test.v.scaled)
T_pair = (T_pred, 𝒟test.T.scaled)

myanimate(xs, name) = animate_prediction(xs, name, 𝒟test, test_file;
                            legend_labels=["GP(u,v,T)","Truth"], directory=output_gif_directory)
myanimate(u_pair, "u")
myanimate(v_pair, "v")
myanimate(T_pair, "T")
save_frame_n(100, u_pair, "u", 𝒟test, test_file; legend_labels=["GP", "truth"], filename="u_GP_$(test_file)", directory=output_gif_directory)
save_frame_n(100, v_pair, "v", 𝒟test, test_file; legend_labels=["GP", "truth"], filename="v_GP_$(test_file)", directory=output_gif_directory)
save_frame_n(100, T_pair, "T", 𝒟test, test_file; legend_labels=["GP", "truth"], filename="T_GP_$(test_file)", directory=output_gif_directory)

write(o, "GP prediction error on u........ $(mse(u_pair)) \n")
write(o, "GP prediction error on v........ $(mse(v_pair)) \n")
write(o, "GP prediction error on T........ $(mse(T_pair)) \n")

# Close output file
close(o)

# tpoint = 100
# split_vector(uvT) = (uvT[1:Nz], uvT[Nz+1:2*Nz], uvT[2*Nz+1:end])
# u_pred, v_pred, T_pred = split_vector(sol[:,tpoint])
# p1 = plot(u_pred, zC_coarse, label="GP_DE")
# plot!(𝒟test.u.scaled[:,tpoint], zC_coarse, label="truth")
# p2 = plot(v_pred, zC_coarse, label="GP_DE")
# plot!(𝒟test.v.scaled[:,tpoint], zC_coarse, label="truth")
# p3 = plot(T_pred, zC_coarse, label="GP_DE")
# plot!(𝒟test.T.scaled[:,tpoint], zC_coarse, label="truth")
# layout = @layout [a b c]
# p = plot(p1, p2, p3, layout=layout)
# png(p, "hello.png")


##
using OceanTurb

U⁰ = 𝒟test.u.coarse[:,1]
V⁰ = 𝒟test.v.coarse[:,1]
T⁰ = 𝒟test.T.coarse[:,1]

#KPP Parameterization (no training)
les = read_les_output(test_file)
parameters = KPP.Parameters() # default parameters
KPP_model = closure_kpp_full_evolution(parameters,U⁰,V⁰,T⁰,t,les)
u_pred, v_pred, T_pred = KPP_model()

u_KPP = (𝒟test.scalings["u"](u_pred), 𝒟test.u.scaled)
v_KPP = (𝒟test.scalings["v"](v_pred), 𝒟test.v.scaled)
T_KPP = (𝒟test.scalings["T"](T_pred), 𝒟test.T.scaled)
mse(u_KPP)
mse(v_KPP)
mse(T_KPP)
save_frame_n(100, u_KPP, "u", 𝒟test, test_file; legend_labels=["KPP(U⁰,V⁰,T⁰)", "truth"], filename="u_KPP_$(test_file)", directory=output_gif_directory)
save_frame_n(100, v_KPP, "v", 𝒟test, test_file; legend_labels=["KPP(U⁰,V⁰,T⁰)", "truth"], filename="v_KPP_$(test_file)", directory=output_gif_directory)
save_frame_n(100, T_KPP, "T", 𝒟test, test_file; legend_labels=["KPP(U⁰,V⁰,T⁰)", "truth"], filename="T_KPP_$(test_file)", directory=output_gif_directory)
animate_prediction(u_KPP, "u", 𝒟test, test_file; legend_labels=["KPP(U⁰,V⁰,T⁰)", "truth"], filename="u_KPP_$(test_file)", directory=output_gif_directory)
animate_prediction(v_KPP, "v", 𝒟test, test_file; legend_labels=["KPP(U⁰,V⁰,T⁰)", "truth"], filename="v_KPP_$(test_file)", directory=output_gif_directory)
animate_prediction(T_KPP, "T", 𝒟test, test_file; legend_labels=["KPP(U⁰,V⁰,T⁰)", "truth"], filename="T_KPP_$(test_file)", directory=output_gif_directory)

#TKE Parameterization (no training; use default parameters)
les = read_les_output(test_file)
parameters = TKEMassFlux.TKEParameters() # default parameters
TKE_model = closure_tke_full_evolution(parameters,U⁰,V⁰,T⁰,t,les)
u_pred, v_pred, T_pred = TKE_model()
u_TKE = (𝒟test.scalings["u"](u_pred), 𝒟test.u.scaled)
v_TKE = (𝒟test.scalings["v"](v_pred), 𝒟test.v.scaled)
T_TKE = (𝒟test.scalings["T"](T_pred), 𝒟test.T.scaled)
mse(u_TKE)
mse(v_TKE)
mse(T_TKE)
save_frame_n(100, u_TKE, "u", 𝒟test, test_file; legend_labels=["TKE(U⁰,V⁰,T⁰)", "truth"], filename="u_TKE_$(test_file)", directory=output_gif_directory)
save_frame_n(100, v_TKE, "v", 𝒟test, test_file; legend_labels=["TKE(U⁰,V⁰,T⁰)", "truth"], filename="v_TKE_$(test_file)", directory=output_gif_directory)
save_frame_n(100, T_TKE, "T", 𝒟test, test_file; legend_labels=["TKE(U⁰,V⁰,T⁰)", "truth"], filename="T_TKE_$(test_file)", directory=output_gif_directory)
animate_prediction(u_TKE, "u", 𝒟test, test_file; legend_labels=["TKE(U⁰,V⁰,T⁰)", "truth"], filename="u_TKE_$(test_file)", directory=output_gif_directory)
animate_prediction(v_TKE, "v", 𝒟test, test_file; legend_labels=["TKE(U⁰,V⁰,T⁰)", "truth"], filename="v_TKE_$(test_file)", directory=output_gif_directory)
animate_prediction(T_TKE, "T", 𝒟test, test_file; legend_labels=["TKE(U⁰,V⁰,T⁰)", "truth"], filename="T_TKE_$(test_file)", directory=output_gif_directory)


## NN

using BSON

file = BSON.load("u_SWWC_test.bson")
data_100 = file[100]
NDE_u = data_100[:NDE]
truth_u = data_100[:truth]

file = BSON.load("v_SWWC_test.bson")
data_100 = file[100]
NDE_v = data_100[:NDE]
truth_v = data_100[:truth]

file = BSON.load("T_SWWC_test.bson")
data_100 = file[100]
NDE_T = data_100[:NDE]
truth_T = data_100[:truth]

save_frame_n(1, (NDE_u,truth_u), "u", 𝒟test, test_file; legend_labels=["NDE", "truth"], filename="u_NN_$(test_file)", directory=output_gif_directory)
save_frame_n(1, (NDE_v,truth_v), "v", 𝒟test, test_file; legend_labels=["NDE", "truth"], filename="v_NN_$(test_file)", directory=output_gif_directory)
save_frame_n(1, (NDE_T,truth_T), "T", 𝒟test, test_file; legend_labels=["NDE", "truth"], filename="T_NN_$(test_file)", directory=output_gif_directory)
