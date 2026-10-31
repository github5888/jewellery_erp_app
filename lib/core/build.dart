/// Build metadata and environment presets.
const kBuild = 'v2.1 Enterprise';
const kBuildVersion = kBuild;

const kProductionApiUrl = 'https://pos.hrpocket.in/api/v1';
const kProductionWebOrigin = 'https://pos.hrpocket.in';

class ServerPreset {
  const ServerPreset({
    required this.label,
    required this.subtitle,
    required this.url,
  });
  final String label;
  final String subtitle;
  final String url;
}

const kServerPresets = <ServerPreset>[
  ServerPreset(
    label: 'Production Cloud (pos.hrpocket.in)',
    subtitle: 'Primary Enterprise Cloud Gateway',
    url: 'https://pos.hrpocket.in/api/v1',
  ),
  ServerPreset(
    label: 'Android Emulator Loopback',
    subtitle: 'Local NestJS dev server via 10.0.2.2:3000',
    url: 'http://10.0.2.2:3000/api/v1',
  ),
  ServerPreset(
    label: 'iOS Simulator / Desktop Localhost',
    subtitle: 'Local NestJS dev server on port 3000',
    url: 'http://localhost:3000/api/v1',
  ),
];
