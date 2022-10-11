using UnityEngine;
using System;

[ExecuteInEditMode, ImageEffectAllowedInSceneView]
public class BloomEffect : MonoBehaviour
{
    private const int BoxDownPrefilterPass = 0;
    private const int BoxDownPass = 1;
    private const int BoxUpPass = 2;
    private const int ApplyBloomPass = 3;
    private const int DebugBloomPass = 4;

    [SerializeField]
    private Shader bloomShader;

    [NonSerialized]
    private Material bloom;

    [Range(1, 16), SerializeField]
    private int iterations = 1;

    [Range(0, 10), SerializeField]
    private float threshold = 1;

    [Range(0, 1), SerializeField]
    private float softThreshold = 0.5f;

    [Range(0, 10), SerializeField]
    private float intensity = 1;

    [SerializeField]
    private bool debug = false;

    private void OnRenderImage(RenderTexture source, RenderTexture destination) {

        // Using a custom shader to improve the quality of the filtering
        if (bloom == null && bloomShader != null) {
            bloom = new Material(bloomShader);
            bloom.hideFlags = HideFlags.HideAndDontSave;
        }

        //bloom.SetFloat("_Threshold", threshold);
        //bloom.SetFloat("_SoftThreshold", softThreshold);

        // Calculating soft curve values for the prefilter step. It's done here
        // to avoid recalculating values that would stay the same for the all
        // the frame
        float knee = threshold * softThreshold;
        Vector4 filter;
        filter.x = threshold;
        filter.y = filter.x - knee;
        filter.z = 2f * knee;
        filter.w = 0.25f / (knee + 0.00001f);
        bloom.SetVector("_Filter", filter);

        // Intensity is commonly tuned in gamma space, so we have to convert
        // to linear space before sending it to the shader (which works in linear space)
        bloom.SetFloat("_Intensity", Mathf.GammaToLinearSpace(intensity));

        // Using half of the original texture resolution we are effectively
        // downsampling the original texture thanks to the bilinear filtering (or a 
        // custom shader if provided), thus applying a blur effect with a
        // kernel of 2x2 pixels.
        int width = source.width / 2;
        int height = source.height / 2;
        RenderTextureFormat format = source.format;

        // Initialize the depth buffer to 0, since we want to write to the texture
        // for each pixel, no matter the depth value of the source texture
        // (Typical approach for a post-process effect)
        int depthBuffer = 0;

        RenderTexture[] textures = new RenderTexture[16];

        RenderTexture currentDestination = textures[0] = RenderTexture.GetTemporary(
            width, height, depthBuffer, format
        );
        Graphics.Blit(source, currentDestination, bloom, BoxDownPrefilterPass);
        RenderTexture currentSource = currentDestination;

        // To increase the blur effect, we cannot simply use a single temporary
        // texture with size == width / 4, height / 4 or width / 8, height / 2 or more,
        // because we'd end up discarding pixels, since the bilinear filtering will
        // still look to just the adjacent pixels, and, with a divisor greater than 2,
        // this will discard pixels far than 2 from the downsampled pixels.
        // Instead, we have to iterate the downsample process using temporary textures
        // with a resolution that is half of the previous one each time.
        int i = 0;
        for (i = 1; i < iterations; i++) {
            width /= 2;
            height /= 2;
            // Avoid downsampling to resolutions with size == 0. Also, sizes == 1 does
            // not add much, so we stop the algorythm when height drop below 2 (we use
            // height as reference, since most screen has height lesser then the width,
            // so they represent the worst case dimension, but to support mobile with
            // portrait mode we should check for both width and height).
            if (height < 2) {
                break;
            }
            currentDestination = textures[i] = RenderTexture.GetTemporary(
                width, height, depthBuffer, format
            );
            Graphics.Blit(currentSource, currentDestination, bloom, BoxDownPass);
            // RenderTexture.ReleaseTemporary(currentSource);
            currentSource = currentDestination;
        }

        // We also need to avoid loosing quality in the upsampling phase (the weight
        // mask keep being 4x4, regardless the source resolution). So we apply the
        // same logic: we iterate back all the stored textures so that, each time, we
        // upsample from a size to its double. We iterate backwards starting from
        // i (which is "iterations" at the beginning) - 2 so we skip the smallest
        // texture, which is the first source.
        for (i -= 2; i >= 0; i--) {
            currentDestination = textures[i];
            textures[i] = null;
            Graphics.Blit(currentSource, currentDestination, bloom, BoxUpPass);
            RenderTexture.ReleaseTemporary(currentSource);
            currentSource = currentDestination;
        }

        // The blit operation from the last temporary texture to the destination texture
        // implies an upsampling to the original texture size. This is performed
        // automatically via bilinear upsampling, which produce output pixels in
        // blocks of 4x4, based on the input 2x2 pixels (assuming the temporary texture
        // is half the original size) and a weight mask (see tutorial for the weight
        // mask composition).
        // Moreover: bloom requires to add the result of eachg upsampled texture to the
        // corresponding downsampled texture with the same resolution. This works fine
        // for intermediate iterations (thanks to the Blend One One mode in the
        // BoxUpPass) but it doesn't work for the final pass, since the destination
        // texture is empty (or invalid, depending of how Unity reuses textures).
        // To solve this, a custom ApplyBloomPass is used, that add the source texture
        // to the final texture manually, passing the source to the _SourceTex variable
        // of the shader.
        if (debug) {
            Graphics.Blit(currentSource, destination, bloom, DebugBloomPass);    
        } else {
            bloom.SetTexture("_SourceTex", source);
            Graphics.Blit(currentSource, destination, bloom, ApplyBloomPass);
        }
        RenderTexture.ReleaseTemporary(currentSource);
    }
}
