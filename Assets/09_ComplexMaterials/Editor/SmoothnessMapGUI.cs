using UnityEngine;
using UnityEditor;

public class SmoothnessMapGUI : ShaderGUI {

    enum SmoothnessSource {
        Uniform, Albedo, Metallic
    }

    static GUIContent staticLabel = new GUIContent();
    Material target;
    MaterialEditor editor;
    MaterialProperty[] properties;

    public override void OnGUI(MaterialEditor editor, MaterialProperty[] properties) {

        this.target = editor.target as Material;
        this.editor = editor;
        this.properties = properties;
        this.DoMain();
        this.DoSecondary();
    }

    void DoMain() {
        GUILayout.Label("Main Maps", EditorStyles.boldLabel);

        MaterialProperty mainTex = this.FindProperty("_MainTex");
        editor.TexturePropertySingleLine(
            MakeLabel(mainTex, "Albedo (RGB)"),
            mainTex,
            this.FindProperty("_Tint")
        );
        this.DoMetallic();
        this.DoSmoothness();
        this.DoNormals();
        editor.TextureScaleOffsetProperty(mainTex);
    }

    void DoSecondary() {
        GUILayout.Label("Secondary Maps", EditorStyles.boldLabel);

        MaterialProperty detailTex = this.FindProperty("_DetailTex");
        editor.TexturePropertySingleLine(
            MakeLabel(detailTex, "Albedo (RGB) multiplied by 2"),
            detailTex
        );
        this.DoSecondaryNormals();
        editor.TextureScaleOffsetProperty(detailTex);
    }

    void DoMetallic() {
        MaterialProperty map = this.FindProperty("_MetallicMap");
        // BeginChangeCheck / EndChangeCheck block allow to detect changes
        // in the GUI widget added in it and return the result of the change
        // in the returned value of the EndChangeCheck function.
        EditorGUI.BeginChangeCheck();
        editor.TexturePropertySingleLine(
            MakeLabel(map, "Metallic (R)"),
            map,
            map.textureValue ? null : this.FindProperty("_Metallic")
        );
        if (EditorGUI.EndChangeCheck()) {
            // A change has made in the Metallic line
            // (either the texture or the slider changed):
            // Update the _METALLIC_MAP keyword
            // (avoid to do this at every GUI update save time, because keyword
            // definition could be expensive)
            this.SetKeyword("_METALLIC_MAP", map.textureValue);
        }
    }

    void DoSmoothness() {

        // Firstly, we get the original smoothness value
        SmoothnessSource source = SmoothnessSource.Uniform;
        if (this.IsKeywordEnabled("_SMOOTHNESS_ALBEDO")) {
            source = SmoothnessSource.Albedo;
        } else if (this.IsKeywordEnabled("_SMOOTHNESS_METALLIC")) {
            source = SmoothnessSource.Metallic;
        }

        MaterialProperty slider = this.FindProperty("_Smoothness");
        EditorGUI.indentLevel += 2;
        editor.ShaderProperty(slider, MakeLabel(slider));
        EditorGUI.indentLevel += 1;
        EditorGUI.BeginChangeCheck();
        // The EnumPopup method return the updated state, if a change has been made
        source = (SmoothnessSource)EditorGUILayout.EnumPopup(MakeLabel("Source"), source);
        if (EditorGUI.EndChangeCheck()) {
            // This allow Undo on the following actions
            this.RecordAction("Smoothness Source");
            // Update the keyword based on the updated state
            this.SetKeyword("_SMOOTHNESS_ALBEDO", source == SmoothnessSource.Albedo);
            this.SetKeyword("_SMOOTHNESS_METALLIC", source == SmoothnessSource.Metallic);
        }
        EditorGUI.indentLevel -= 3;
    }

    void DoNormals() {
        MaterialProperty map = this.FindProperty("_NormalMap");
        editor.TexturePropertySingleLine(
            MakeLabel(map),
            map,
            map.textureValue ? this.FindProperty("_BumpScale") : null
        );
    }

    void DoSecondaryNormals() {
        MaterialProperty map = this.FindProperty("_DetailNormalMap");
        editor.TexturePropertySingleLine(
            MakeLabel(map),
            map,
            map.textureValue ? this.FindProperty("_DetailBumpScale") : null
        );
    }

    private MaterialProperty FindProperty(string name) {
        return FindProperty(name, this.properties);
    }

    private void SetKeyword(string keyword, bool state) {
        if (state) {
            this.target.EnableKeyword(keyword);
        } else {
            this.target.DisableKeyword(keyword);
        }
    }

    private bool IsKeywordEnabled(string keyword) {
        return this.target.IsKeywordEnabled(keyword);
    }

    void RecordAction(string label) {
        this.editor.RegisterPropertyChangeUndo(label);
    }

    private static GUIContent MakeLabel(string text, string tooltip = null) {
        staticLabel.text = text;
        staticLabel.tooltip = tooltip;
        return staticLabel;
    }

    private static GUIContent MakeLabel(MaterialProperty property, string tooltip = null) {
        staticLabel.text = property.displayName;
        staticLabel.tooltip = tooltip;
        return staticLabel;
    }
}
