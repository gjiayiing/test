export default `
#define USE_NORMAL_SHADING

uniform float view_distance;
uniform vec3 viewArea_color;
uniform vec3 shadowArea_color;
uniform float percentShade;

uniform sampler2D colorTexture;
uniform sampler2D shadowMap;
uniform mat4 shadowMap_matrix;

uniform vec3 cameraPosition_WC;
uniform vec4 shadowMap_camera_positionEC;

uniform vec4 shadowMap_normalOffsetScaleDistanceMaxDistanceAndDarkness;
uniform vec4 shadowMap_texelSizeDepthBiasAndNormalShadingSmooth;

in vec2 v_textureCoordinates;
out vec4 FragColor;

/* -------------------------
   Helpers
------------------------- */

vec4 toEye(vec2 uv, float depth) {
    float x = uv.x * 2.0 - 1.0;
    float y = uv.y * 2.0 - 1.0;
    vec4 posEC = czm_inverseProjection * vec4(x, y, depth, 1.0);
    return posEC / posEC.w;
}

float getDepth(vec4 packedDepth) {
    float z_window = czm_unpackDepth(packedDepth);
    z_window = czm_reverseLogDepth(z_window);
    float n = czm_depthRange.near;
    float f = czm_depthRange.far;
    return (2.0 * z_window - n - f) / (f - n);
}

/* -------------------------
   MAIN
------------------------- */

void main() {

    vec4 color = texture(colorTexture, v_textureCoordinates);
    vec4 depthPacked = texture(czm_globeDepthTexture, v_textureCoordinates);

    // sky
    if (depthPacked.r >= 1.0) {
        FragColor = color;
        return;
    }

    float depth = getDepth(depthPacked);
    vec4 positionEC = toEye(v_textureCoordinates, depth);

    /* =========================================================
       🔥 VIEWSHED BOUNDARY (THIS IS THE GREEN BOX)
       ========================================================= */

    // Project fragment into sensor shadow space
    vec4 shadowPos = shadowMap_matrix * positionEC;
    shadowPos /= shadowPos.w;

    // HARD rectangular footprint (frustum projection)
    if (any(lessThan(shadowPos.xyz, vec3(0.0))) ||
        any(greaterThan(shadowPos.xyz, vec3(1.0)))) {
        FragColor = color;
        return;

    }

    // HARD range cutoff (this defines footprint length)
    vec4 sensorWC = czm_inverseView * vec4(shadowMap_camera_positionEC.xyz, 1.0);
    vec4 fragWC   = czm_inverseView * vec4(positionEC.xyz, 1.0);

    if (distance(sensorWC.xyz, fragWC.xyz) > view_distance) {
        FragColor = color;
        return;
    }

    /* =========================================================
       SHADOW VISIBILITY
       ========================================================= */

    czm_shadowParameters params;
    params.texelStepSize = shadowMap_texelSizeDepthBiasAndNormalShadingSmooth.xy;
    params.depthBias     = shadowMap_texelSizeDepthBiasAndNormalShadingSmooth.z;
    params.normalShadingSmooth =
        shadowMap_texelSizeDepthBiasAndNormalShadingSmooth.w;
    params.darkness =
        shadowMap_normalOffsetScaleDistanceMaxDistanceAndDarkness.w;

    params.depthBias *= max(depth * 0.01, 1.0);

    vec3 lightDirEC = normalize(positionEC.xyz - shadowMap_camera_positionEC.xyz);
    params.nDotL = clamp(dot(vec3(1.0), -lightDirEC), 0.0, 1.0);

    params.texCoords = shadowPos.xy;
    params.depth     = shadowPos.z;

    float visibility = czm_shadowVisibility(shadowMap, params);

    if (visibility == 1.0) {
        FragColor = mix(color, vec4(viewArea_color, 1.0), percentShade);
    } else {
        FragColor = mix(color, vec4(shadowArea_color, 1.0), percentShade);
    }
}
`;
