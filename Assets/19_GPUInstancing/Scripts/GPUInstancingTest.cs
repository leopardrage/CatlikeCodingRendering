using UnityEngine;

public class GPUInstancingTest : MonoBehaviour
{
    public Transform prefab;
    public int instances = 5000;
    public float radius = 50f;

    void Start()
    {
        // We can reuse the same material property block for all instances
        // since the SetPropertyBlock actually copies the given property block.
        MaterialPropertyBlock properties = new MaterialPropertyBlock();

        for (int i = 0; i < this.instances; i++) {
            Transform t = Instantiate(this.prefab);
            t.localPosition = Random.insideUnitSphere * this.radius;
            t.SetParent(this.transform);

            // Assigning a new color to the main material after the object has
            // been instantiated, implicitly create a new material. This nullifies
            // the benefits of GPU Instancing, since the material for batched meshes
            // must be the same.
            /* t.GetComponent<MeshRenderer>().material.color =
                new Color(Random.value, Random.value, Random.value); */

            // Alternative approach using the MaterialPropertyBlock class:
            // Property blocks allow to override material properties
            properties.SetColor(
                "_Color", new Color(Random.value, Random.value, Random.value)
            );

            MeshRenderer r = t.GetComponent<MeshRenderer>();
            if (r) {
                // Case of a single object with a mesh renderer
                r.SetPropertyBlock(properties);
            } else {
                // Case of a root object whose children have mesh renderers
                // (typical of models that support LOD groups)
                for (int ci = 0; ci < t.childCount; ci++) {
                    r = t.GetChild(ci).GetComponent<MeshRenderer>();
                    if (r) {
                        r.SetPropertyBlock(properties);
                    }
                }
            }
        }
    }
}
