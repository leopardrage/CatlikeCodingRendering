using System.Collections;
using System.Collections.Generic;
using UnityEngine;

[ExecuteInEditMode, ImageEffectAllowedInSceneView]
public class DepthOfFieldEffect : MonoBehaviour
{
    [HideInInspector]
    public Shader dofShader;

    [System.NonSerialized]
    Material dofMaterial;

    [Range(0.1f, 100f)]
    public float focusDistance = 10f;
    [Range(0.1f, 10f)]
    public float focusRange = 3f;
    [Range(1f, 10f)]
    public float bokehRadius = 4f;

    private const int circleOfConfusionPass = 0;
    private const int preFilterPass = 1;
    private const int bokehPass = 2;
    private const int postFilterPass = 3;
    private const int combinePass = 4;

    private void OnRenderImage(RenderTexture source, RenderTexture destination)
    {
        if (this.dofMaterial == null)
        {
            this.dofMaterial = new Material(this.dofShader);
            this.dofMaterial.hideFlags = HideFlags.HideAndDontSave;
        }

        this.dofMaterial.SetFloat("_FocusDistance", this.focusDistance);
        this.dofMaterial.SetFloat("_FocusRange", this.focusRange);
        this.dofMaterial.SetFloat("_BokehRadius", this.bokehRadius);

        RenderTexture coc = RenderTexture.GetTemporary(
            source.width, source.height, 0,
            RenderTextureFormat.RHalf, RenderTextureReadWrite.Linear
        );

        int width = source.width / 2;
        int height = source.height / 2;
        RenderTextureFormat format = source.format;
        RenderTexture dof0 = RenderTexture.GetTemporary(width, height, 0, format);
        RenderTexture dof1 = RenderTexture.GetTemporary(width, height, 0, format);

        this.dofMaterial.SetTexture("_CoCTex", coc);
        this.dofMaterial.SetTexture("_DoFTex", dof0);

        Graphics.Blit(source, coc, this.dofMaterial, circleOfConfusionPass);
        Graphics.Blit(source, dof0, this.dofMaterial, preFilterPass);
        Graphics.Blit(dof0, dof1, this.dofMaterial, bokehPass);
        Graphics.Blit(dof1, dof0, this.dofMaterial, postFilterPass);
        Graphics.Blit(source, destination, this.dofMaterial, combinePass);
        
        RenderTexture.ReleaseTemporary(coc);
        RenderTexture.ReleaseTemporary(dof0);
        RenderTexture.ReleaseTemporary(dof1);
    }
}
