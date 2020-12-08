"""
# Description
Takes NzxNt arrays of profiles for variables u, v, T and returns
Nzx(Nt-1) arrays of the profile evolution for u, v, T, u'w', v'w', and w'T'
the horizontally averaged flux for variable V.

# Arguments
Unscaled u, v, T, z, t, and f
"""
function reconstruct_flux_profiles(u, v, T, z, t, f)

    Δz = diff(z)
    Δt = diff(t, dims=1)'

    Nz,Nt = size(T)

    dVdt = (T[:,2:Nt] .- T[:,1:Nt-1]) ./ Δt # Nz x (Nt-1) array of approximate dVdt values
    u = u[:,1:Nt-1]
    v = v[:,1:Nt-1]
    T = T[:,1:Nt-1]

    """ evaluates wϕ = ∫ ∂z(wϕ) dz """
    function wϕ(∂z_wϕ)
        ans = zeros(Nz+1, Nt-1) # one fewer column than T
        for i in 1:Nt-1, h in 1:Nz-1
            ans[h+1, i] = ans[h, i] + Δz[h] * ∂z_wϕ[h, i]
        end
        return ans
    end

    duw_dz = -dVdt .+ f*v
    dvw_dz = -dVdt .- f*u
    dwT_dz = -dVdt

    # println(size(wV(duw_dz)))
    # u, v, T, uw, vw, wT, t
    return (u, v, T, wϕ(duw_dz), wϕ(dvw_dz), wϕ(dwT_dz), t[1:Nt-1])
end

using OceanParameterizations, Plots

𝒟 = data("strong_wind")

𝒟_reconstructed = data("strong_wind_weak_heating", reconstruct_fluxes=true)

𝒟_reconstructed
z = 𝒟_reconstructed.uw.z
t = 𝒟_reconstructed.t
Nt = length(𝒟.t)
output_gif_directory = "TestReconstructFluxes"
animate_gif((𝒟_reconstructed.uw.coarse, 𝒟.uw.coarse[:,1:Nt-1]), z, t, "uw",
            x_label=["∫(-du/dt + fv)dz", "truth"],
            filename="uw_reconstructed",
            directory=output_gif_directory)
animate_gif((𝒟_reconstructed.vw.coarse, 𝒟.vw.coarse[:,1:Nt-1]), z, t, "vw",
            x_label=["∫(-dv/dt - fu)dz", "truth"],
            filename="vw_reconstructed",
            directory=output_gif_directory)
animate_gif((𝒟_reconstructed.wT.coarse, 𝒟.wT.coarse[:,1:Nt-1]), z, t, "wT",
            x_label=["∫(-dw/dt)dz", "truth"],
            filename="wT_reconstructed",
            directory=output_gif_directory)
