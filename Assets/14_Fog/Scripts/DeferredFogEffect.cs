using System.Collections;
using System.Collections.Generic;
using UnityEngine;
using System;

// Remember to disable this component if Fog is disabled in scene Environment
// Settings in order to optimize rendering
[ExecuteInEditMode]
public class DeferredFogEffect : MonoBehaviour
{
    public Shader deferredFog;

    [NonSerialized]
    Material fogMaterial;

    [NonSerialized]
    Camera deferredCamera;

    [NonSerialized]
    Vector3[] frustumCorners;

    // This is needed just to pass frustumCorners to our shader
    // since we cannot pass Vector3, just Vector4.
    [NonSerialized]
    Vector4[] vectorArray;

    // Unity checks if a camera has components that implements this method
    // and calls it after the camera has finished rendering to perform
    // post-process logic. If more components implement this method, their
    // implementations are called in the order in which the components are
    // attached to the camera object.
    // The ImageEffectOpaque attribute tells Unity to call this method
    // After the opaque objects have been rendered but before the others.
    // This is needed to handle transparent objects, since they don't write
    // on the depth buffer and thus their depth values would be the ones of the
    // closest opaque object behind them (or 1, if nothing is behing them)
    // generating incorrect color values (fog would be too strong).
    // The transparent objects' fog will be rendered through the forward fog.
    [ImageEffectOpaque]
    private void OnRenderImage(RenderTexture src, RenderTexture dest) {
        if (this.fogMaterial == null) {
            this.fogMaterial = new Material(this.deferredFog);
            this.deferredCamera = GetComponent<Camera>();
            this.frustumCorners = new Vector3[4];
            this.vectorArray = new Vector4[4];
        }
        // Calculate the 4 vectors that start from the camera,
        // pass through each corner of a rect ((0,0), (1,1)), the entire screen,
        // and go as far as the distance of the far plane. Interpolating
        // between these corners we can have all the rays passing through each
        // pixels of the screen. Those rays' length would be the distance to be used
        // to calculate the distance-based fog
        this.deferredCamera.CalculateFrustumCorners(
            new Rect(0f, 0f, 1f, 1f),
            this.deferredCamera.farClipPlane,
            this.deferredCamera.stereoActiveEye,
            this.frustumCorners
            );

        // the returned corners are clockwise ordered starting from bottom-left.
        // However the quad used to render the image effect has its corner vertices
        // ordered anti-clockwise, starting from bottom-left. We change the order
        // to match the quad's.
        this.vectorArray[0] = this.frustumCorners[0];
        this.vectorArray[1] = this.frustumCorners[3];
        this.vectorArray[2] = this.frustumCorners[1];
        this.vectorArray[3] = this.frustumCorners[2];
        this.fogMaterial.SetVectorArray("_FrustumCorners", this.vectorArray);

        Graphics.Blit(src, dest, this.fogMaterial);
    }
}
