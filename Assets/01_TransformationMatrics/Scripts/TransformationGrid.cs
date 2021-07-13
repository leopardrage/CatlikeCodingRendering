using UnityEngine;
using System.Collections.Generic;

public class TransformationGrid : MonoBehaviour {

	public Transform prefab;

	public int gridResolution = 10;

	Transform[] grid;

	List<Transformation> transformations;

	Matrix4x4 transformation;

	private void Awake () {
		
		this.grid = new Transform[this.gridResolution * this.gridResolution * this.gridResolution];
		for (int i = 0, z = 0; z < this.gridResolution; z++) {
			for (int y = 0; y < this.gridResolution; y++) {
				for (int x = 0; x < this.gridResolution; x++, i++) {
					this.grid[i] = CreateGridPoint(x, y, z);
				}
			}
		}
		transformations = new List<Transformation>();
	}

	private Transform CreateGridPoint (int x, int y, int z) {
		Transform point = Instantiate<Transform>(this.prefab);
		point.localPosition = GetCoordinates(x, y, z);
		point.GetComponent<MeshRenderer>().material.color = new Color(
			(float)x / this.gridResolution,
			(float)y / this.gridResolution,
			(float)z / this.gridResolution
		);
		return point;
	}

	private Vector3 GetCoordinates (int x, int y, int z) {
		return new Vector3(
			x - (this.gridResolution - 1) * 0.5f,
			y - (this.gridResolution - 1) * 0.5f,
			z - (this.gridResolution - 1) * 0.5f
		);
	}

	void Update () {
		UpdateTransformation();
		for (int i = 0, z = 0; z < gridResolution; z++) {
			for (int y = 0; y < gridResolution; y++) {
				for (int x = 0; x < gridResolution; x++, i++) {
					grid[i].localPosition = TransformPoint(x, y, z);
				}
			}
		}
	}

	void UpdateTransformation () {
		GetComponents<Transformation>(transformations);
		if (transformations.Count > 0) {
			transformation = transformations[0].Matrix;
			for (int i = 1; i < transformations.Count; i++) {
				transformation = transformations[i].Matrix * transformation;
			}
		}
	}

	Vector3 TransformPoint (int x, int y, int z) {
		Vector3 coordinates = GetCoordinates(x, y, z);
		return transformation.MultiplyPoint(coordinates);
	}
}