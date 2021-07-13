using UnityEngine;

public class EmissiveOscillator : MonoBehaviour
{
    MeshRenderer emissiveRenderer;
    Material emissiveMaterial;

    void Start() {
        emissiveRenderer = GetComponent<MeshRenderer>();
        emissiveMaterial = emissiveRenderer.material;    
    }

    void Update() {
        Color c = Color.Lerp(
            Color.white,
            Color.black,
            Mathf.Sin(Time.time * Mathf.PI * 0.5f + 0.5f)
        );
        emissiveMaterial.SetColor("_Emission", c);
        // This is neded to notify the realtime GI system that it has work to do.
        // Without this update, indirect light won't affected.
        // emissiveRenderer.UpdateGIMaterials();
        // However, the UpdateGIMaterials method trigger a complete update of the object's
        // emission, which uses its meta pass. This is necessary when the emission is
        // more complex than a solid color, e.g. a texture, but is also quite expansive.
        // If we can assume we only work with solid color, we can use the following
        // method as a cheaper shortcut to update the emission color for the current
        // renderer.
        DynamicGI.SetEmissive(emissiveRenderer, c);
    }
}
