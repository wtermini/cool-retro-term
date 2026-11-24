/*
 * CRT effect shaders for the native macOS front end.
 *
 * These are Metal ports of the Qt app's shaders in app/shaders:
 *   burn_in.frag          -> burnin_fragment
 *   terminal_dynamic.*    -> dynamic_fragment (noise, jitter, sync, glow line,
 *                            burn-in, rasterization, chroma, flicker)
 *   terminal_static.frag  -> final_fragment (curvature, reflection, RGB shift,
 *                            bloom, brightness)
 *   terminal_frame.frag   -> frameColorAt (bezel, rounded corners, glass)
 *
 * This file is compiled at runtime with MTLDevice.makeLibrary(source:), so it
 * needs no Metal toolchain at build time.
 *
 * Copyright (c) 2013-2021 "Filippo Scognamiglio"
 * https://github.com/Swordfish90/cool-retro-term
 *
 * This file is part of cool-retro-term, licensed under the GNU General Public
 * License version 3 or (at your option) any later version.
 */

#include <metal_stdlib>
using namespace metal;

// Keep in sync with CRTUniforms in CRTRenderer.swift (same field order).
struct CRTUniforms {
    float4 fontColor;
    float4 backgroundColor;
    float4 frameColor;
    float4 contentRect;          // terminal area in screen UV: origin.xy, size.zw
    float2 viewportSize;         // view size in points
    float2 virtualResolution;    // terminal pixels across the whole screen
    float2 jitterDisplacement;
    float2 noiseScale;
    float time;
    float staticNoise;
    float glowingLine;
    float chromaColor;
    float jitter;
    float horizontalSync;
    float horizontalSyncStrength;
    float flickering;
    float burnIn;
    float burnInTime;
    float burnInLastUpdate;
    float burnInPrevUpdate;
    float rasterization;         // 0 none, 1 scanlines, 2 pixels, 3 subpixels, 4 modern
    float rasterizationIntensity;
    float screenCurvature;
    float rgbShift;
    float bloom;
    float brightness;
    float frameSize;
    float frameShininess;
    float screenRadius;          // in points
    float ambientLight;
    float pixelated;             // 1 to sample the terminal with nearest filtering
};

struct VertexOut {
    float4 position [[position]];
    float2 uv;                   // (0,0) top left, (1,1) bottom right
};

constant float kBlurWeights[5] = { 0.227027, 0.1945946, 0.1216216, 0.054054, 0.016216 };

static float min2(float2 v) { return min(v.x, v.y); }
static float max2(float2 v) { return max(v.x, v.y); }
static float prod2(float2 v) { return v.x * v.y; }
static float rand2(float2 v) { return fract(sin(dot(v, float2(12.9898, 78.233))) * 43758.5453); }
static float rgb2grey(float3 v) { return dot(v, float3(0.21, 0.72, 0.04)); }

static float2 distortCoordinates(float2 coords, constant CRTUniforms &u) {
    float2 padded = coords * (float2(1.0) + u.frameSize * 2.0) - u.frameSize;
    float2 cc = padded - float2(0.5);
    float dist = dot(cc, cc) * u.screenCurvature;
    return padded + cc * (1.0 + dist) * dist;
}

static float2 contentCoords(float2 screenUV, constant CRTUniforms &u) {
    return (screenUV - u.contentRect.xy) / u.contentRect.zw;
}

// One triangle that covers the whole render target.
vertex VertexOut fullscreen_vertex(uint vid [[vertex_id]]) {
    float2 p = float2(float((vid << 1) & 2), float(vid & 2));
    VertexOut out;
    out.position = float4(p * 2.0 - 1.0, 0.0, 1.0);
    out.uv = float2(p.x, 1.0 - p.y);
    return out;
}

// MARK: - Burn-in accumulation (terminal texture space)

fragment float4 burnin_fragment(VertexOut in [[stage_in]],
                                constant CRTUniforms &u [[buffer(0)]],
                                texture2d<float> source [[texture(0)]],
                                texture2d<float> accumulated [[texture(1)]]) {
    constexpr sampler s(address::clamp_to_edge, filter::linear);
    float3 txtColor = source.sample(s, in.uv).rgb;
    float4 accColor = accumulated.sample(s, in.uv);

    float prevMask = accColor.a;
    float blurDecay = clamp((u.burnInLastUpdate - u.burnInPrevUpdate) * u.burnInTime, 0.0, 1.0);
    blurDecay = max(0.0, blurDecay - prevMask);
    float3 color = max(accColor.rgb - float3(blurDecay), txtColor);

    float currMask = step(rgb2grey(color), rgb2grey(txtColor));
    return float4(color, currMask);
}

// MARK: - Dynamic pass (flat screen space)

static float3 applyRasterization(float2 screenCoords, float3 texel, float2 virtualRes,
                                 float intensity, int mode) {
    if (mode == 0 || mode == 4 || intensity <= 0.0) {
        return texel;
    }

    const float INTENSITY = 0.30;
    const float BRIGHTBOOST = 0.30;

    float3 result = texel;
    if (mode == 3) {
        const float SUBPIXELS = 3.0;
        float3 offsets = float3(M_PI_F) * float3(0.5, 0.5 - 2.0 / 3.0, 0.5 - 4.0 / 3.0);
        float2 omega = float2(M_PI_F) * 2.0 * virtualRes;
        float2 angle = screenCoords * omega;
        float3 xfactors = (SUBPIXELS + sin(angle.x + offsets)) / (SUBPIXELS + 1.0);
        result = texel * xfactors;
    }

    float3 pixelHigh = ((1.0 + BRIGHTBOOST) - (0.2 * result)) * result;
    float3 pixelLow  = ((1.0 - INTENSITY) + (0.1 * result)) * result;

    float2 coords = fract(screenCoords * virtualRes) * 2.0 - float2(1.0);
    float mask;
    if (mode == 2) {
        coords = coords * coords;
        mask = 1.0 - coords.x - coords.y;
    } else {
        mask = 1.0 - abs(coords.y);
    }

    float3 rasterizationColor = mix(pixelLow, pixelHigh, mask);
    return mix(texel, rasterizationColor, intensity);
}

static float randomPass(float2 coords, constant CRTUniforms &u) {
    return fract(smoothstep(-120.0, 0.0, coords.y - (u.virtualResolution.y + 120.0) * fract(u.time * 0.15)));
}

static float3 convertWithChroma(float3 inColor, constant CRTUniforms &u) {
    float grey = rgb2grey(inColor);
    float denom = max(grey, 0.0001);
    float3 foregroundColor = mix(u.fontColor.rgb, inColor * u.fontColor.rgb / denom, u.chromaColor);
    return mix(u.backgroundColor.rgb, foregroundColor, grey);
}

fragment float4 dynamic_fragment(VertexOut in [[stage_in]],
                                 constant CRTUniforms &u [[buffer(0)]],
                                 texture2d<float> content [[texture(0)]],
                                 texture2d<float> burnInTexture [[texture(1)]],
                                 texture2d<float> noise [[texture(2)]]) {
    constexpr sampler smooth(address::clamp_to_zero, filter::linear);
    constexpr sampler sharp(address::clamp_to_zero, filter::nearest);
    constexpr sampler tiled(address::repeat, filter::linear);

    // Per-frame values (computed in the vertex shader in the Qt version).
    float4 frameNoise = noise.sample(tiled, float2(fract(u.time / 2.048), fract(u.time / 1048.576)));
    float brightness = 1.0 + (frameNoise.g - 0.5) * u.flickering;
    float randval = u.horizontalSyncStrength - frameNoise.r;
    float distortionScale = step(0.0, randval) * randval * u.horizontalSyncStrength * u.horizontalSync;
    float distortionFreq = mix(4.0, 40.0, frameNoise.g);

    float2 uv = in.uv;
    float distance = length(float2(0.5) - uv);

    float2 coords = uv;
    coords.x += sin((coords.y + u.time) * distortionFreq) * distortionScale;

    float4 noiseTexel = noise.sample(tiled, u.noiseScale * coords
                                     + float2(fract(u.time / 0.051), fract(u.time / 0.237)));
    float2 txtCoords = coords + (noiseTexel.ba - float2(0.5)) * u.jitterDisplacement * u.jitter;

    float color = 0.0001;
    color += noiseTexel.a * u.staticNoise * (1.0 - distance * 1.3);
    color += randomPass(coords * u.virtualResolution, u) * u.glowingLine;

    float2 terminalUV = contentCoords(txtCoords, u);
    float3 txtColor = u.pixelated > 0.5
        ? content.sample(sharp, terminalUV).rgb
        : content.sample(smooth, terminalUV).rgb;
    txtColor *= 1.0 + max(u.bloom, 0.0);

    if (u.burnIn > 0.0) {
        float4 txtBlur = burnInTexture.sample(smooth, terminalUV);
        float blurDecay = clamp((u.time - u.burnInLastUpdate) * u.burnInTime, 0.0, 1.0);
        float3 burnInColor = 0.65 * (txtBlur.rgb - float3(blurDecay)) * (1.0 - txtBlur.a);
        txtColor = max(txtColor, burnInColor);
    }

    txtColor += float3(color);
    txtColor = applyRasterization(uv, txtColor, u.virtualResolution,
                                  u.rasterizationIntensity, int(u.rasterization + 0.5));

    float3 finalColor = convertWithChroma(txtColor, u) * brightness;
    return float4(finalColor, 1.0);
}

// MARK: - Bloom blur (separable)

fragment float4 blur_fragment(VertexOut in [[stage_in]],
                              constant float2 &direction [[buffer(0)]],
                              texture2d<float> source [[texture(0)]]) {
    constexpr sampler s(address::clamp_to_edge, filter::linear);
    float3 sum = source.sample(s, in.uv).rgb * kBlurWeights[0];
    for (int i = 1; i < 5; i++) {
        float2 offset = direction * float(i);
        sum += source.sample(s, in.uv + offset).rgb * kBlurWeights[i];
        sum += source.sample(s, in.uv - offset).rgb * kBlurWeights[i];
    }
    return float4(sum, 1.0);
}

// MARK: - Bezel

static float roundedRectSdfPixels(float2 p, float2 topLeft, float2 bottomRight,
                                  float radiusPixels, float2 viewportSize) {
    float2 sizePixels = (bottomRight - topLeft) * viewportSize;
    float2 centerPixels = (topLeft + bottomRight) * 0.5 * viewportSize;
    float2 localPixels = p * viewportSize - centerPixels;
    float2 halfSize = sizePixels * 0.5 - float2(radiusPixels);
    float2 d = abs(localPixels) - halfSize;
    return length(max(d, float2(0.0))) + min(max(d.x, d.y), 0.0) - radiusPixels;
}

static float4 frameColorAt(float2 staticCoords, constant CRTUniforms &u) {
    float2 coords = distortCoordinates(staticCoords, u);

    float screenRadiusPixels = u.screenRadius;
    float edgeSoftPixels = 1.0;
    float seamWidth = max(screenRadiusPixels, 0.5) / min2(u.viewportSize);

    float e = min(smoothstep(-seamWidth, seamWidth, coords.x - coords.y),
                  smoothstep(-seamWidth, seamWidth, coords.x - (1.0 - coords.y)));
    float s = min(smoothstep(-seamWidth, seamWidth, coords.y - coords.x),
                  smoothstep(-seamWidth, seamWidth, coords.x - (1.0 - coords.y)));
    float w = min(smoothstep(-seamWidth, seamWidth, coords.y - coords.x),
                  smoothstep(-seamWidth, seamWidth, (1.0 - coords.x) - coords.y));
    float n = min(smoothstep(-seamWidth, seamWidth, coords.x - coords.y),
                  smoothstep(-seamWidth, seamWidth, (1.0 - coords.x) - coords.y));

    float distPixels = roundedRectSdfPixels(coords, float2(0.0), float2(1.0),
                                            screenRadiusPixels, u.viewportSize);
    float frameShadow = (e * 0.66 + w * 0.66 + n * 0.33 + s);
    frameShadow *= smoothstep(0.0, edgeSoftPixels * 5.0, distPixels);

    float frameAlpha = 1.0 - u.frameShininess * 0.4;

    float inScreen = smoothstep(0.0, edgeSoftPixels, -distPixels);
    float alpha = mix(frameAlpha, mix(0.0, 0.3, u.ambientLight), inScreen);
    // max() guards pow() against negative input outside the screen.
    float glassBase = max(prod2(coords * (1.0 - coords.yx)) * 25.0, 0.0);
    float glass = clamp(u.ambientLight * pow(glassBase, 0.5) * inScreen, 0.0, 1.0);
    float3 frameTint = u.frameColor.rgb * frameShadow;
    float noise = rand2(staticCoords * u.viewportSize) - 0.5;
    frameTint = clamp(frameTint + float3(noise * 0.04), 0.0, 1.0);
    float3 color = mix(frameTint, float3(glass), inScreen);

    return float4(color, alpha);
}

// MARK: - Final pass (curved screen + bezel, to the drawable)

fragment float4 final_fragment(VertexOut in [[stage_in]],
                               constant CRTUniforms &u [[buffer(0)]],
                               texture2d<float> screen [[texture(0)]],
                               texture2d<float> bloomTexture [[texture(1)]]) {
    constexpr sampler s(address::clamp_to_edge, filter::linear);
    float2 uv = in.uv;

    float2 curved = distortCoordinates(uv, u);
    float2 inside = step(float2(0.0), curved) - step(float2(1.0), curved);
    float shownDraw = max2(inside);
    float isScreen = min2(inside);
    float isReflection = shownDraw - isScreen;
    float2 txtCoords = curved * (-1.0 + 2.0 * step(float2(0.0), curved) - 2.0 * step(float2(1.0), curved));

    float3 txtColor = screen.sample(s, txtCoords).rgb;

    if (u.rgbShift > 0.0) {
        float2 displacement = float2(u.rgbShift, 0.0);
        float3 rightColor = screen.sample(s, txtCoords + displacement).rgb;
        float3 leftColor = screen.sample(s, txtCoords - displacement).rgb;
        txtColor.r = leftColor.r * 0.10 + rightColor.r * 0.30 + txtColor.r * 0.60;
        txtColor.g = leftColor.g * 0.20 + rightColor.g * 0.20 + txtColor.g * 0.60;
        txtColor.b = leftColor.b * 0.30 + rightColor.b * 0.10 + txtColor.b * 0.60;
    }

    float3 finalColor = txtColor * shownDraw;

    float3 bloomColor = bloomTexture.sample(s, txtCoords).rgb;
    if (u.bloom > 0.0) {
        finalColor += clamp(bloomColor * isScreen * u.bloom, 0.0, 0.5);
        finalColor /= 1.0 + max(u.bloom, 0.0);
    }

    float3 reflectionColor = mix(bloomColor * 2.0, finalColor, u.frameShininess * 0.5);
    finalColor = mix(finalColor, reflectionColor, isReflection);

    finalColor *= u.brightness;

    float grain = rand2(uv) - 0.5;
    finalColor = clamp(finalColor + float3(grain * 0.025), 0.0, 1.0);

    float4 frame = frameColorAt(uv, u);
    finalColor = mix(finalColor, frame.rgb, frame.a);

    return float4(finalColor, 1.0);
}
