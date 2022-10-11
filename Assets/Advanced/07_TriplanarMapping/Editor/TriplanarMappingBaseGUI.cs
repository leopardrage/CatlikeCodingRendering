using UnityEngine;
using UnityEditor;

public class TriplanarMappingBaseGUI : ShaderGUI {

    static GUIContent staticLabel = new GUIContent();

    protected Material target;
    protected MaterialEditor editor;
    MaterialProperty[] properties;

    bool shouldShowAlphaCutoff;

    public override void OnGUI(MaterialEditor editor, MaterialProperty[] properties) {

        this.target = editor.target as Material;
        this.editor = editor;
        this.properties = properties;
    }

    protected MaterialProperty FindProperty(string name) {
        return FindProperty(name, this.properties);
    }

    protected void SetKeyword(string keyword, bool state) {
        // Loop all targets to update keywords for all selected materials
        if (state) {
            foreach (Material material in editor.targets)
            {
                material.EnableKeyword(keyword);
            }
        } else {
            foreach (Material material in editor.targets)
            {
                material.DisableKeyword(keyword);
            }
        }
    }

    protected bool IsKeywordEnabled(string keyword) {
        return this.target.IsKeywordEnabled(keyword);
    }

    protected void RecordAction(string label) {
        this.editor.RegisterPropertyChangeUndo(label);
    }

    protected static GUIContent MakeLabel(string text, string tooltip = null) {
        staticLabel.text = text;
        staticLabel.tooltip = tooltip;
        return staticLabel;
    }

    protected static GUIContent MakeLabel(MaterialProperty property, string tooltip = null) {
        staticLabel.text = property.displayName;
        staticLabel.tooltip = tooltip;
        return staticLabel;
    }
}
