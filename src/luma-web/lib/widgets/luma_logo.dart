import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// The Luma application logo rendered from an inline SVG.
///
/// Use [size] to control both width and height (the logo is square).
class LumaLogo extends StatelessWidget {
  final double size;

  const LumaLogo({super.key, this.size = 32});

  static const String _svg = '''
<svg width="48" height="48" viewBox="0 0 48 48" fill="none" xmlns="http://www.w3.org/2000/svg">
<g filter="url(#filter0_iii_3051_46883)">
<g clip-path="url(#clip0_3051_46883)">
<rect width="48" height="48" rx="12" fill="#22262F"/>
<rect width="48" height="48" fill="url(#paint0_linear_3051_46883)"/>
<g filter="url(#filter1_d_3051_46883)">
<path fill-rule="evenodd" clip-rule="evenodd" d="M24.9194 21.383L33.1689 13.1335L31.4012 11.3657L25.2855 17.4814V6.5H22.7855V17.4814L16.6698 11.3657L14.902 13.1335L23.1516 21.383L24.0355 22.2669L24.9194 21.383ZM26.6856 23.1508L34.9352 14.9012L36.703 16.669L30.5873 22.7847H41.5003V25.2847H30.5873L36.703 31.4004L34.9352 33.1681L26.6856 24.9186L25.8018 24.0347L26.6856 23.1508ZM13.1338 33.1681L21.3834 24.9186L22.2673 24.0347L21.3834 23.1508L13.1338 14.9012L11.366 16.669L17.4817 22.7847H6.50195V25.2847H17.4817L11.366 31.4004L13.1338 33.1681ZM23.1516 26.6864L14.902 34.9359L16.6698 36.7037L22.7855 30.588V41.5H25.2855V30.588L31.4012 36.7037L33.1689 34.9359L24.9194 26.6864L24.0355 25.8025L23.1516 26.6864Z" fill="url(#paint1_linear_3051_46883)"/>
</g>
</g>
<rect x="1" y="1" width="46" height="46" rx="11" stroke="url(#paint2_linear_3051_46883)" stroke-width="2"/>
</g>
<defs>
<filter id="filter0_iii_3051_46883" x="0" y="-3" width="48" height="54" filterUnits="userSpaceOnUse" color-interpolation-filters="sRGB">
<feFlood flood-opacity="0" result="BackgroundImageFix"/>
<feBlend mode="normal" in="SourceGraphic" in2="BackgroundImageFix" result="shape"/>
<feColorMatrix in="SourceAlpha" type="matrix" values="0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 127 0" result="hardAlpha"/>
<feOffset dy="-3"/>
<feGaussianBlur stdDeviation="1.5"/>
<feComposite in2="hardAlpha" operator="arithmetic" k2="-1" k3="1"/>
<feColorMatrix type="matrix" values="0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0.1 0"/>
<feBlend mode="normal" in2="shape" result="effect1_innerShadow_3051_46883"/>
<feColorMatrix in="SourceAlpha" type="matrix" values="0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 127 0" result="hardAlpha"/>
<feOffset dy="3"/>
<feGaussianBlur stdDeviation="1.5"/>
<feComposite in2="hardAlpha" operator="arithmetic" k2="-1" k3="1"/>
<feColorMatrix type="matrix" values="0 0 0 0 1 0 0 0 0 1 0 0 0 0 1 0 0 0 0.1 0"/>
<feBlend mode="normal" in2="effect1_innerShadow_3051_46883" result="effect2_innerShadow_3051_46883"/>
<feColorMatrix in="SourceAlpha" type="matrix" values="0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 127 0" result="hardAlpha"/>
<feMorphology radius="1" operator="erode" in="SourceAlpha" result="effect3_innerShadow_3051_46883"/>
<feOffset/>
<feComposite in2="hardAlpha" operator="arithmetic" k2="-1" k3="1"/>
<feColorMatrix type="matrix" values="0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0.2 0"/>
<feBlend mode="normal" in2="effect2_innerShadow_3051_46883" result="effect3_innerShadow_3051_46883"/>
</filter>
<filter id="filter1_d_3051_46883" x="3.16667" y="3.16667" width="41.6667" height="46.6667" filterUnits="userSpaceOnUse" color-interpolation-filters="sRGB">
<feFlood flood-opacity="0" result="BackgroundImageFix"/>
<feColorMatrix in="SourceAlpha" type="matrix" values="0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 127 0" result="hardAlpha"/>
<feMorphology radius="1.66667" operator="erode" in="SourceAlpha" result="effect1_dropShadow_3051_46883"/>
<feOffset dy="2.5"/>
<feGaussianBlur stdDeviation="2.5"/>
<feComposite in2="hardAlpha" operator="out"/>
<feColorMatrix type="matrix" values="0 0 0 0 0.141176 0 0 0 0 0.141176 0 0 0 0 0.141176 0 0 0 0.1 0"/>
<feBlend mode="normal" in2="BackgroundImageFix" result="effect1_dropShadow_3051_46883"/>
<feBlend mode="normal" in="SourceGraphic" in2="effect1_dropShadow_3051_46883" result="shape"/>
</filter>
<linearGradient id="paint0_linear_3051_46883" x1="24" y1="5.96047e-07" x2="26" y2="48" gradientUnits="userSpaceOnUse">
<stop stop-color="white" stop-opacity="0"/>
<stop offset="1" stop-color="white" stop-opacity="0.12"/>
</linearGradient>
<linearGradient id="paint1_linear_3051_46883" x1="24.0011" y1="6.5" x2="24.0011" y2="41.5" gradientUnits="userSpaceOnUse">
<stop stop-color="white" stop-opacity="0.8"/>
<stop offset="1" stop-color="white" stop-opacity="0.5"/>
</linearGradient>
<linearGradient id="paint2_linear_3051_46883" x1="24" y1="0" x2="24" y2="48" gradientUnits="userSpaceOnUse">
<stop stop-color="white" stop-opacity="0.12"/>
<stop offset="1" stop-color="white" stop-opacity="0"/>
</linearGradient>
<clipPath id="clip0_3051_46883">
<rect width="48" height="48" rx="12" fill="white"/>
</clipPath>
</defs>
</svg>
''';

  @override
  Widget build(BuildContext context) {
    return SvgPicture.string(
      _svg,
      width: size,
      height: size,
    );
  }
}
