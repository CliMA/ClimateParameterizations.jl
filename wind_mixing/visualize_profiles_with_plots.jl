using Plots
using OceanParameterizations

reconstruct_fluxes = true
println("Reconstruct fluxes? $(reconstruct_fluxes)")

enforce_surface_fluxes = true
println("Enforce surface fluxes? $(enforce_surface_fluxes)")

output_directory=pwd()*"/ProfileVisuals/reconstruct_$(reconstruct_fluxes)/enforce_surface_fluxes_$(enforce_surface_fluxes)"
mkpath(output_directory)

files =  ["free_convection", "strong_wind", "strong_wind_no_coriolis", "weak_wind_strong_cooling",
          "strong_wind_weak_cooling", "strong_wind_weak_heating"]

file_labels = Dict(
    "free_convection" => "Free convection",
    "strong_wind" => "Strong wind",
    "strong_wind_no_coriolis" => "Strong wind, no rotation",
    "weak_wind_strong_cooling" => "Weak wind, strong cooling",
    "strong_wind_weak_cooling" => "Strong wind, weak cooling",
    "strong_wind_weak_heating" => "Strong wind, weak heating"
)

Ts = Dict()
for file in files
    Ts[file] = data(file, reconstruct_fluxes=reconstruct_fluxes,
                    enforce_surface_fluxes=enforce_surface_fluxes) # <: OceananigansData
end

x_lims = Dict(
    "uw" => (-10,2),
    "vw" => (-4,4.5),
    "wT" => (-1.5,0.7),
    "T" => (19.6,20)
)

f = Dict(
    "uw" => 𝒟 -> 𝒟.uw.coarse,
    "vw" => 𝒟 -> 𝒟.vw.coarse,
    "wT" => 𝒟 -> 𝒟.wT.coarse,
    "T"  => 𝒟 -> 𝒟.T.coarse
)

zs = Dict(
    "uw" => 𝒟 -> 𝒟.uw.z,
    "vw" => 𝒟 -> 𝒟.vw.z,
    "wT" => 𝒟 -> 𝒟.wT.z,
    "T"  => 𝒟 -> 𝒟.T.z
)

# legend_placement = Dict(
#     "uw" => :bottomleft,
#     "vw" => :bottomright,
#     "wT" => :right
# )

legend_placement = Dict(
    "uw" => false,
    "vw" => false,
    "wT" => false,
    "T"  => false,
)

scaling_factor = Dict(
    "uw" => 1e4,
    "vw" => 1e4,
    "wT" => 1e4,
    "T" => 1
)

x_labels = Dict(
    "uw" => "U'W' x 10⁴ (m²/s²)",
    "vw" => "V'W' x 10⁴ (m²/s²)",
    "wT" => "W'T' x 10⁴ (C⋅m/s)",
    "T" => "T (C)"
)

titles = Dict(
    "uw" => "Zonal momentum flux, U'W'",
    "vw" => "Meridional momentum flux, V'W'",
    "wT" => "Temperature flux, W'T'",
    "T" => "Temperature, T",
)

function plot_frame_i(name, i)
    p = plot(xlabel=x_labels[name], ylabel="Depth (m)", palette=:Paired_6, legend=legend_placement[name], foreground_color_grid=:white, plot_titlefontsize=20)
    # p = plot(xlabel=x_labels[name], xlims = x_lims[name], ylabel="Depth (m)", palette=:Paired_6, legend=legend_placement[name], foreground_color_grid=:white, plot_titlefontsize=20)
    for (file, T) in Ts
        plot!(f[name](T)[:,i].*scaling_factor[name], zs[name](T), title = titles[name], label="$(file)", linewidth=3)
    end
    plot!(size=(400,500))
    p
end

p1 = plot_frame_i("uw", 288)
savefig(p1, output_directory*"/uw_last_frame.pdf")

p2 = plot_frame_i("vw", 288)
savefig(p2, output_directory*"/vw_last_frame.pdf")

p3 = plot_frame_i("wT", 288)
savefig(p3, output_directory*"/wT_last_frame.pdf")

pT = plot_frame_i("T", 288)
savefig(pT, output_directory*"/T_last_frame.pdf")

p4 = plot(grid=false, showaxis=false, palette=:Paired_6, ticks=nothing)
for (file, T) in Ts
    plot!(1, label=file_labels[file], legend=:left, size=(200,600))
end
p4
savefig(p4, output_directory*"/legend_last_frame.pdf")

layout = @layout [a b c d]
p = plot(p1,p2,p3,p4,layout=layout, size=(1600,400), tickfontsize=12)
savefig(p, output_directory*"/all_last_frame_new_suite.pdf")

layout = @layout [a b c d e]
p = plot(p1,p2,p3,pT,p4,layout=layout, size=(1600,400), tickfontsize=12)
savefig(p, output_directory*"/all_last_frame_new_suite_with_T.pdf")

## ANIMATION

# add x_lims for animations
function plot_frame_i(name, i)
    p = plot(xlabel=x_labels[name], xlims = x_lims[name], ylabel="Depth (m)", palette=:Paired_6, legend=legend_placement[name], foreground_color_grid=:white, plot_titlefontsize=20)
    for (file, T) in Ts
        plot!(f[name](T)[:,i].*scaling_factor[name], zs[name](T), title = titles[name], label="$(file)", linewidth=3)
    end
    plot!(size=(400,500))
    p
end

function animate_all(name, Ts)
    anim = @animate for i in 1:288
        plot_frame_i(name, i)
    end
    return anim
end

save_animation(anim, filename) = gif(anim, filename, fps=20)
save_animation(animate_all("uw", Ts), output_directory*"/uw.gif")
save_animation(animate_all("vw", Ts), output_directory*"/vw.gif")
save_animation(animate_all("wT", Ts), output_directory*"/wT.gif")
save_animation(animate_all("T", Ts), output_directory*"/T.gif")
