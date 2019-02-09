﻿Shader "Custom/CloudRendering"
{
	Properties
	{

		
		_CloudBase("Cloud Base Texture", 3D) = "white" {}

		_CloudDetail("Cloud Detail Texture", 3D) = "white" {}

		_NoiseTex("Texture for Random", 2D) = "white"{}
		_CloudWeather("Cloud Coverage Texture", 2D) = "white" {}

		_ViewRange("Cloud View Range" ,float) = 50000
		_EarthRadius("Earth Radius", float) = 200000
		_LowerHeight("Atmosphere Lower Height", float) = 1000
		_UpperHeight("Atmosphere Upper Height", float) = 4000


		_DensityCutoff("Density Cutoff", Range(0,0.2)) = 0.2
		_CloudCoverage("Cloud Coverage", Range(0.0,1)) = 0.5

		_CloudBaseScale("Cloud Base Shape Scale", Range(0.4,1.8)) = 1
		_CloudDetailScale("Cloud Detail Shape Scale", Range(0.5,2)) = 1
		_CloudWeatherScale("Cloud Weather Scale", Range(0.7,10)) = 1
		_CloudTransmittance("Cloud Overall Transmittance", Range(0.0010,0.0250)) = 0.010

		_DetailErodeStrength("Detail Erode Strength", Range(0.00,0.6)) = 0.3


		_AmbientColor("Ambient Color", Color) = (0.2,0.2,0.2,1.0)
		_AmbientStrength("Skylight Strength", Range(0,10)) = 2

		_DensityClampLow("Density Clamping Low Value" ,Range(0,1)) = 0.1
		_DensityClampHigh("Density Clamping Hight Value" ,Range(1.1,2)) = 1.5
		_CloudEdgeFactor("Cloud Edge Factor" ,Range(0.01,0.2)) = 0.1


		_PowderFactor("Powder Effect Factor", Range(0.05,0.5)) = 0.15

		_LightAdjust("Light Adjustment", Range(0,10)) = 1


		_DirectionalSpread("Directional Spread", Range(0,50)) = 30
		_DirectionalStrength("Directional Strength", Range(0,10)) = 4

		_Test("Test",Range(1,5)) = 1

		_LowDensityThreshold("Low Density Threshold",Range(0,0.2)) = 0.05

		_FinalAdjust("Final Light Adjustment", Range(-0.4,0.4)) = 0

	}
	SubShader
	{
		// No culling or depth
		Cull Off ZWrite Off ZTest Always

		Pass
		{
			CGPROGRAM
			#pragma vertex vert
			#pragma fragment frag
			
			#include "UnityCG.cginc"


			float4x4 _LastFrameVPMatrix;


			sampler3D _CloudBase;
			sampler3D _CloudDetail;
			sampler2D _LastFrameTex;
			sampler2D _CloudWeather;
			sampler2D _NoiseTex;

			const float MAX_FLOAT =1.0e+30;

			float _EarthRadius;
			float _LowerHeight;
			float _UpperHeight;
			float3 _CameraPos;
			float _CloudBaseScale;
			float _CloudWeatherScale;
			float _CloudDetailScale;

			float _DetailErodeStrength;

			float _CloudTransmittance;
			float _Test;
			float _ViewRange;

			float _DensityCutoff;

			float _DensityClampLow;
			float _DensityClampHigh;
			float _CloudCoverage;

			float _CloudEdgeFactor;

			float _PowderFactor;
			float _LightAdjust;

			float _DirectionalSpread;
			float _DirectionalStrength;

				
			float4 _AmbientColor;
			float _AmbientStrength;

			float _FinalAdjust;

			float _LowDensityThreshold;

			struct appdata
			{
				float4 vertex : POSITION;
				float2 uv : TEXCOORD0;
				float4 ray : TEXCOORD1;
			};

			struct v2f
			{
				float4 vertex : SV_POSITION;
				float2 uv : TEXCOORD0;
				float3 worldPos : TEXCOORD1;
				float4 interpolatedRay : TEXCOORD2;
			};





			float2 RaySphereIntersectT(float3 ray, float height)
			{
				float a = dot(ray,ray);
				float b = 2 * (_EarthRadius + _CameraPos.y) * ray.y;
				float c = -2 * _EarthRadius * height - height * height + _CameraPos.y * _CameraPos.y + 2 * _EarthRadius * _CameraPos.y;
				float delta = b * b - 4 * a * c;

				if (delta < 0) return float2(MAX_FLOAT, MAX_FLOAT);

				float t1 = - (b + sqrt(delta)) / (2 * a); float t2 = - (b - sqrt(delta)) / (2 * a);
				if (t1 < 0) t1 = MAX_FLOAT; if (t2 < 0) t2 = MAX_FLOAT;
				return float2(t1,t2);
			}

			void CalculateThicknessFactor(float midHeight, float cloudThick, float linePos, out float heightSignal, out float heightEnhanceThres)
			{
				float thickness = min(midHeight , 1 - midHeight) * cloudThick;
				float a = midHeight - thickness; float b = midHeight + thickness;
				heightSignal = saturate(-4 / (a - b)/(a - b) * (linePos - a) * (linePos - b));
				heightEnhanceThres = (b - linePos)/(b - a);
			}




			float SampleDensity(float3 pos, float linePos)
			{
				//float4 s = tex3D(_CloudBase,float3(pos.x/ 10000 / _CloudBaseScale, pos.z/10000 / _CloudBaseScale, linePos / 2));
				//float c = tex2D(_CloudWeather,float2(pos.x/ 10000 / _CloudWeatherScale, pos.z/10000 / _CloudWeatherScale));

				float4 s = tex3Dlod(_CloudBase,float4(pos.x/ 10000 / _CloudBaseScale, pos.z/10000 / _CloudBaseScale, linePos / _CloudBaseScale / 2 ,0));

				float random = tex2Dlod(_NoiseTex, float4(frac(pos.y + _Time.x), frac(pos.x + _Time.y),0,0)).r ;
				//float c = tex2Dlod(_CloudWeather,float4(pos.x / 10000 / _CloudWeatherScale, pos.z/10000 / _CloudWeatherScale,0,4));

				float c = tex2Dlod(_CloudWeather,float4((pos.x + 100 *  sin(random*6.2832) ) / 10000 / _CloudWeatherScale, (pos.z + 100 * cos(random*6.2832) ) /10000 / _CloudWeatherScale,0,4));
//
//				c /= 2;

				if (_CloudCoverage <= 0.5) {c = lerp(0,c,_CloudCoverage * 2);} else {c = lerp(c,1,_CloudCoverage * 2 - 1);}
				float density = s.r * 0.45 + s.g * 0.3 + s.b * 0.15 + s.a * 0.15;
				density *= 3;
				density *= c;

				float heightSignal;
				float heightEnhanceThres;

				CalculateThicknessFactor(0.5, c, linePos,heightSignal, heightEnhanceThres);


				density = smoothstep(_DensityClampLow,_DensityClampHigh,density);
				density *= pow (heightSignal,_Test);
				//density = smoothstep(0,heightEnhanceThres,density);
				return density;
			}

			float SampleDetail(float3 pos, float linePos)
			{
				float4 s = tex3Dlod(_CloudDetail,float4(pos.x/ 2500 / _CloudDetailScale, pos.z/2500 / _CloudDetailScale, 4 * linePos/ _CloudDetailScale ,0));
				return s.r * 0.33 + s.g * 0.33 + s.b * 0.33;
			}


//			float3 GetConeSamplingDir(float3 lightDir, float3 pos)
//			{
//				float a = lightDir.x; float b = lightDir.y; float c = lightDir.z;
//				float3 tangent = float3(0,0,1);
//				if ( a != 0 || b != 0){
//					if (c != 0)
//					{ 
//						tangent = normalize(float3(1,1,-(a+b)/c));
//					} else
//					{
//						tangent = normalize(float3(-b,a,0));
//					}
//				}
//				float3 bitangent = normalize(cross(tangent,lightDir));
//				float3x3 M = {bitangent,tangent,lightDir}; M = transpose(M);
//				float random = tex2Dlod(_NoiseTex, float4(frac(pos.y + _SinTime.x), frac(pos.x + _SinTime.y),0,0)).r ;
//				float r = sqrt(random * 0.5);
//				random = tex2Dlod(_NoiseTex, float4(random + frac(2 * pos.y + _SinTime.x), 2 * random + frac(0.5 * pos.x + _SinTime.y),0,0)).r ;
//				float3 offsetVector = float3(r * cos(random * 6.2832),0, r * sin(random * 6.2832));
//				offsetVector = mul(M, offsetVector);
//				return normalize(offsetVector + lightDir);
//			}








			float SampleSunLight(float3 rayPos, float linePos, float3 lightDir, float density)
			{
				
				//float3 shadowRayPos = rayPos + lightDir * 100 ;
				//float shadowLinePos = linePos + lightDir.y * 100  / (_UpperHeight - _LowerHeight);




				//float3 samplingDir = GetConeSamplingDir(lightDir,rayPos);

				//float3 shadowRayPos = rayPos + samplingDir * 200 * random;
				//float shadowLinePos = linePos + samplingDir.y * 200 * random / (_UpperHeight - _LowerHeight);

				float random = tex2Dlod(_NoiseTex, float4(frac(rayPos.y + _SinTime.x), frac(rayPos.z + _SinTime.y),0,0)).r ;
				float3 shadowRayPos = rayPos + lightDir * 600 * (0.5 + random) ;
				float3 shadowLinePos = linePos + lightDir.y * 600  * (0.5 + random) / (_UpperHeight - _LowerHeight);
				float newDensity = SampleDensity(shadowRayPos, shadowLinePos);
				float diff = saturate(density - newDensity);
				diff = smoothstep(0.00,_CloudEdgeFactor, diff)* density ;

				//random = tex2Dlod(_NoiseTex, float4(frac(rayPos.y + random), frac(rayPos.z + random),0,0)).r ;
				shadowRayPos = rayPos + lightDir * 3000 * (0.5 + random) ;
				shadowLinePos = linePos + lightDir.y * 3000  * (0.5 + random) / (_UpperHeight - _LowerHeight);
				newDensity = SampleDensity(shadowRayPos, shadowLinePos);

				diff *= saturate((1 - newDensity * 2));

				return diff;


			}

			float3 ToneMapping (float3 x)
			{
				const float A = 0.15;
				const float B = 0.50;
				const float C = 0.10;
				const float D = 0.20;
				const float E = 0.02;
				const float F = 0.30;
				return ((x*(A*x + C * B) + D * E) / (x*(A*x + B) + D * F)) - E / F;
			}



			float4 RayMarching(float3 start, float3 end, int sampleStep, float3 lightDir,float2 uv)
			{
				
				float3 stepVector = (end - start) / (float)sampleStep;
				float3 rayDir = normalize(stepVector);
				float stepSize = length(stepVector);
				float stepLineSize = 1/ (float)sampleStep;
				float3 rayPos = start ; float rayLinePos = 0;
				float density = 0;
				float directionalFactor = pow(max(0, dot(rayDir, lightDir)),_DirectionalSpread);
				float3 directionalScattering = float3(1,1,1) * pow(10,_DirectionalStrength) * directionalFactor;
				bool cheap = false;
				uint cumuLowDensity = 0;

				float4 light = float4(0,0,0,1);
				light.a = 1;


				float3 stepVectorTMP = stepVector;
				float3 stepSizeTMP = stepSize;
				float3 stepLineSizeTMP = stepLineSize;
				float3 baseColor = 0;

				for (int i = 0; i < sampleStep; i++)
				{
					float random = tex2Dlod(_NoiseTex, float4(frac(rayPos.y + _SinTime.x), frac(rayPos.x + _SinTime.y),0,0)).r ;
					//random = 0.5;
					rayPos = rayPos +  stepVectorTMP * (random + 0.5);
					rayLinePos = rayLinePos + stepLineSizeTMP  * (random + 0.5);

					density = SampleDensity(rayPos, rayLinePos) - SampleDetail(rayPos, rayLinePos)* _DetailErodeStrength;


					if (density <= _DensityCutoff)  density = 0;
					float transmittanceCurrent = exp(- stepSizeTMP * density * _CloudTransmittance);


					if(length(rayPos - _CameraPos) > _ViewRange) break;
					if (density <= _LowDensityThreshold) { cumuLowDensity += 1; } 
					else 
					{
						cheap = false;
						cumuLowDensity = 0;
						stepSizeTMP = stepSize;
						stepVectorTMP = stepVector;
						stepLineSizeTMP = stepLineSize;
					}
					if (cumuLowDensity >= 5) cheap = true;
					if (light.a<0.15) cheap = true;

					if (cumuLowDensity >= 15 && cumuLowDensity % 15 == 0)
					{
						stepSizeTMP *= 1.5;
						stepVectorTMP *= 1.5;
						stepLineSizeTMP *= 1.5;
					}



					if (cheap) {baseColor = _AmbientColor.rgb ;}
					else
					{
						baseColor = _AmbientColor.rgb + SampleSunLight(rayPos,rayLinePos,lightDir,density) * (float3(1.0,1.0,1.0) * _AmbientStrength + directionalScattering) ;
					}


					float powderEffect =  1 - exp(- stepSizeTMP * density * _CloudTransmittance * 2) + _PowderFactor;
					//powderEffect  =1;

					//light.xyz += light.a  * ( 0.5 + pow(transmittanceCurrent,5)) *baseColor;
					light.xyz += light.a  * powderEffect *baseColor * _LightAdjust;

					light.a *= transmittanceCurrent ;

					if (rayLinePos >= 1) break;
					if (light.a<0.015) break;

				}
				light.xyz = ToneMapping(light.xyz) * (1 + _FinalAdjust);
				//if(light.a >0.999) return float4(1,0,0,0);
				//if(light.a <0.01) return float4(1,0,0,0);
				//if(cumuLowDensity >= 15) return float4(1,0,0,0);
				return light ;
			}



			v2f vert(appdata v)
			{
				v2f o;
				o.vertex = UnityObjectToClipPos(v.vertex);
				o.uv = v.uv.xy;		

				o.interpolatedRay = v.ray;
				o.worldPos = mul(unity_ObjectToWorld,v.vertex);
				return o;
			}



			half4 frag (v2f i) : SV_Target

			{
				_AmbientStrength = pow(_AmbientStrength,2.5);
				i.interpolatedRay = normalize(i.interpolatedRay);
				if (i.interpolatedRay.y < 0.00) return 1;

				float3 lightDir = normalize(_WorldSpaceLightPos0.xyz);

				float3 rayMarchingStart = 0;
				float3 rayMarchingEnd = 0;


				rayMarchingStart = _CameraPos + i.interpolatedRay * RaySphereIntersectT(i.interpolatedRay, _LowerHeight).y;
				rayMarchingEnd = _CameraPos + i.interpolatedRay * RaySphereIntersectT(i.interpolatedRay, _UpperHeight).y;

				float4 reprojectionPoint = float4((rayMarchingStart + rayMarchingEnd) / 2,1);
				float4 lastFrameClipCoord = mul(_LastFrameVPMatrix, reprojectionPoint);

				float2 lastFrameUV  = float2(lastFrameClipCoord.x/lastFrameClipCoord.w, lastFrameClipCoord.y/lastFrameClipCoord.w)* 0.5 + 0.5;
				float4 lastFrameCol = float4(0,0,0,1);
				float lerpFac = 1;
				if(abs(lastFrameClipCoord.x/lastFrameClipCoord.w)<1 && abs(lastFrameClipCoord.y/lastFrameClipCoord.w)<1) 
				{
					 lastFrameCol =  tex2D(_LastFrameTex, lastFrameUV);
					 lerpFac = 0.075;
				}
	
				float4 currentFrameCol = RayMarching(rayMarchingStart, rayMarchingEnd, 64,lightDir,i.uv);
				return lerp(lastFrameCol, currentFrameCol, lerpFac);

			}
			ENDCG
		}
	}
}
