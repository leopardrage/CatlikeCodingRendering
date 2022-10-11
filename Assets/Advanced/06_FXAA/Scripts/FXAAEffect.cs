using UnityEngine;

[ExecuteInEditMode, ImageEffectAllowedInSceneView]
public class FXAAEffect : MonoBehaviour
{
    // 'Calculate' expects the given shader to calculate the luminance
    // autonomously and it's the way the entire tutorial is thought for.
    // 'Alpha' and 'Green' expect that the luminance is already stored in the
    // alpha or green channel of the source texture, assuming it's been calculated by
    // some previous post process effect. This is just to mirror the PostEffectStack V2
    // where, I assume, a dedicated effect exists to calculate the luminance, that is
    // used to provide it to different subsequent effects that need it (like FXAA).
    // In those scenarios, Alpha is of course the preferred one, while Green is
    // provided in case the alpha channel could be unavailable and the raw green
    // value is used instead (which resambles the luminance of a pixel quite well,
    // generally).
    public enum LuminanceMode { Alpha, Green, Calculate }

    public LuminanceMode luminanceSource;

    // Range limits taken from Unity Post Process Stack V2, which uses the following
    // possible values:
    // 0.0833 - upper limit (the start of visible unfiltered edges)
    // 0.0625 - high quality (faster)
    // 0.0312 - visible limit (slower)
    [Range(0.0312f, 0.0833f)]
    public float contrastThreshold = 0.0312f;

    // Range limits taken from Unity Post Process Stack V2, which uses the following
    // possible values:
    // 0.333 - too little (faster)
	// 0.250 - low quality
	// 0.166 - default
	// 0.125 - high quality 
	// 0.063 - overkill (slower)
    // These values represent an additional threshold based on the highest
    // luminance of the each pixel neighborhood. This way we can skip higher constrast
    // pixels in brighter regions. This is because the higher the brighter the
    // neighborhood, the higher the contrast must be to matter (and that, in turn,
    // I think it's because brigher regions tend to have high contrast due to lighting
    // (think about specular light, bloom, etc...) and in those cases, which have
    // nothing to do with jagged lines, you don't want to blend anything).
    [Range(0.063f, 0.333f)]
    public float relativeThreshold = 0.063f;

    // Range limits taken from Unity Post Process Stack V2, which uses the following
    // possible values:
    // 1.00 - upper limit (softer)
	// 0.75 - default amount of filtering
	// 0.50 - lower limit (sharper, less sub-pixel aliasing removal)
	// 0.25 - almost off
	// 0.00 - completely off
    // This might effect sharpness
    [Range(0f, 1f)]
    public float subpixelBlending = 1f;

    // Switch between level 12 edge search and level 28 edge search algorithms
    // when calculating the edge blend factor. The higher quality version
    // (level 28 edge search) improves results with long almost vertical or almost
    // horizontal edges.
    public bool lowQuality;

    // Whether or not convert colors in gamma space before blending (and convert them
    // back to linear after). Since FXAA is not about physics but perception, blending
    // colors in gamma space gives better results. 
    // NOTE: the tutorial states that, if this flag is disabled, input must be provided in
    // gamma space, but it makes no sense, since luminance is calculated based
    // on linear values which you wouldn't have in that case...
    public bool gammaBlending;

    [HideInInspector]
    public Shader fxaaShader;

    [System.NonSerialized]
    Material fxaaMaterial;

    private const int luminancePass = 0;
    private const int fxaaPass = 1;

    private void OnRenderImage(RenderTexture source, RenderTexture destination)
    {
        if (this.fxaaMaterial == null)
        {
            this.fxaaMaterial = new Material(this.fxaaShader);
            this.fxaaMaterial.hideFlags = HideFlags.HideAndDontSave;
        }

        this.fxaaMaterial.SetFloat("_ContrastThreshold", this.contrastThreshold);
        this.fxaaMaterial.SetFloat("_RelativeThreshold", this.relativeThreshold);
        this.fxaaMaterial.SetFloat("_SubpixelBlending", this.subpixelBlending);

        if (lowQuality)
        {
            fxaaMaterial.EnableKeyword("LOW_QUALITY");
        }
        else
        {
            fxaaMaterial.DisableKeyword("LOW_QUALITY");
        }

        if (gammaBlending)
        {
            fxaaMaterial.EnableKeyword("GAMMA_BLENDING");
        }
        else
        {
            fxaaMaterial.DisableKeyword("GAMMA_BLENDING");
        }

        if (luminanceSource == LuminanceMode.Calculate)
        {
            fxaaMaterial.DisableKeyword("LUMINANCE_GREEN");
            RenderTexture luminanceTex = RenderTexture.GetTemporary(
                source.width, source.height, 0, source.format
            );
            Graphics.Blit(source, luminanceTex, this.fxaaMaterial, luminancePass);
            Graphics.Blit(luminanceTex, destination, this.fxaaMaterial, fxaaPass);
            RenderTexture.ReleaseTemporary(luminanceTex);
        }
        else
        {
            if (luminanceSource == LuminanceMode.Green)
            {
                fxaaMaterial.EnableKeyword("LUMINANCE_GREEN");
            }
            else
            {
                fxaaMaterial.DisableKeyword("LUMINANCE_GREEN");
            }
            Graphics.Blit(source, destination, this.fxaaMaterial, fxaaPass);
        }
    }
}
