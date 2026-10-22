# Request: a standard App Service module for the SRE team

Our SRE team operates the web services our product teams build, mostly containerized HTTP APIs, and we're consolidating them onto Azure App Service with one standard module instead of a pile of hand-built apps. The SREs will use this module to deploy and run each service. They know Azure well and think in terms of capacity, availability, health, rollouts, and observability, but they don't want to hand-tune App Service internals for every app. You own every design decision the module makes.
