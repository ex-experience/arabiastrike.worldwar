# Jeddah World — Editor Assembly Checklist

- Create `Content/World/Jeddah/Maps/L_Jeddah_RedSeaAssault` from the Unreal **Open World** level template.
- Confirm World Partition, One File Per Actor, Data Layers and streaming are enabled.
- Add Data Layers: `DL_BaseCity`, `DL_Mission`, `DL_Destruction`, `DL_Seasonal`, `DL_Cinematic`.
- Create HLOD Layers for architecture, city props and vegetation.
- Add `BP_WorldBootstrap_Jeddah` based on `ASWorldBootstrap`.
- Add `BP_EnvironmentDirector_Jeddah` and bind `BP_ApplyEnvironmentState` to Directional Light, Sky Atmosphere, Skylight, Fog, Volumetric Clouds and Niagara weather systems.
- Create district trigger volumes and assign the correct district profile.
- Create spline traffic routes and traffic vehicle Blueprint subclasses.
- Create civilian Blueprint subclasses and spawn anchors.
- Create PCG graphs for street props, parked vehicles, facade variation and vegetation.
- Create encounter Blueprint actors and populate the Dynamic Encounter Director table.
- Build World Partition HLODs and navigation data before multiplayer profiling.
- Run dedicated-server soak tests at 8 and 16 players before increasing ambient population.
