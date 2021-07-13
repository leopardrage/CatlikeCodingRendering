using UnityEngine;
using UnityEditor;

public class CustomInspectorLightingGUI : ShaderGUI {

    static GUIContent staticLabel = new GUIContent();
    MaterialEditor editor;
    MaterialProperty[] properties;

    public override void OnGUI(MaterialEditor editor, MaterialProperty[] properties) {

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
        MaterialProperty slider = this.FindProperty("_Metallic");
        EditorGUI.indentLevel += 2;
        editor.ShaderProperty(slider, MakeLabel(slider));
        EditorGUI.indentLevel -= 2;
    }

    void DoSmoothness() {
        MaterialProperty slider = this.FindProperty("_Smoothness");
        EditorGUI.indentLevel += 2;
        editor.ShaderProperty(slider, MakeLabel(slider));
        EditorGUI.indentLevel -= 2;
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
