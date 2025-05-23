#import bevy_render::view::View
#import bevy_pbr::utils::coords_to_viewport_uv

struct SkyboxUniforms {
	brightness: f32,
	transform: mat4x4<f32>,
#ifdef SIXTEEN_BYTE_ALIGNMENT
	_wasm_padding_8b: u32,
	_wasm_padding_12b: u32,
	_wasm_padding_16b: u32,
#endif
}

@group(0) @binding(0) var skybox: texture_cube<f32>;
@group(0) @binding(1) var skybox_sampler: sampler;
@group(0) @binding(2) var<uniform> view: View;
@group(0) @binding(3) var<uniform> uniforms: SkyboxUniforms;

fn coords_to_ray_direction(position: vec2<f32>, viewport: vec4<f32>) -> vec3<f32> {
    // Using world positions of the fragment and camera to calculate a ray direction
    // breaks down at large translations. This code only needs to know the ray direction.
    // The ray direction is along the direction from the camera to the fragment position.
    // In view space, the camera is at the origin, so the view space ray direction is
    // along the direction of the fragment position - (0,0,0) which is just the
    // fragment position.
    // Use the position on the near clipping plane to avoid -inf world position
    // because the far plane of an infinite reverse projection is at infinity.
    let view_position_homogeneous = view.view_from_clip * vec4(
        coords_to_viewport_uv(position, viewport) * vec2(2.0, -2.0) + vec2(-1.0, 1.0),
        1.0,
        1.0,
    );

    // Transforming the view space ray direction by the skybox transform matrix, it is 
    // equivalent to rotating the skybox itself.
    var view_ray_direction = view_position_homogeneous.xyz / view_position_homogeneous.w;
    view_ray_direction = (view.world_from_view * vec4(view_ray_direction, 0.0)).xyz;

    // Transforming the view space ray direction by the view matrix, transforms the
    // direction to world space. Note that the w element is set to 0.0, as this is a
    // vector direction, not a position, That causes the matrix multiplication to ignore
    // the translations from the view matrix.
    let ray_direction = (uniforms.transform * vec4(view_ray_direction, 0.0)).xyz;

    return normalize(ray_direction);
}

struct VertexOutput {
    @builtin(position) position: vec4<f32>,
};

//  3 |  2.
//  2 |  :  `.
//  1 |  x-----x.
//  0 |  |  s  |  `.
// -1 |  0-----x.....1
//    +---------------
//      -1  0  1  2  3
//
// The axes are clip-space x and y. The region marked s is the visible region.
// The digits in the corners of the right-angled triangle are the vertex
// indices.
@vertex
fn skybox_vertex(@builtin(vertex_index) vertex_index: u32) -> VertexOutput {
    // See the explanation above for how this works.
    let clip_position = vec2(
        f32(vertex_index & 1u),
        f32((vertex_index >> 1u) & 1u),
    ) * 4.0 - vec2(1.0);

    return VertexOutput(vec4(clip_position, 0.0, 1.0));
}

@fragment
fn skybox_fragment(in: VertexOutput) -> @location(0) vec4<f32> {
    let ray_direction = coords_to_ray_direction(in.position.xy, view.viewport);

    // Cube maps are left-handed so we negate the z coordinate.
    let out = textureSample(skybox, skybox_sampler, ray_direction * vec3(1.0, 1.0, -1.0));
    return vec4(out.rgb * uniforms.brightness, out.a);
}
