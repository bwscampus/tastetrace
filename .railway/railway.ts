import { defineRailway, github, postgres, preserve, project, service, volume } from "railway/iac";

export default defineRailway(() => {
  const tastetraceApiDb = postgres("tastetrace-api-db", { region: "us-west2" });
  const Postgres = postgres("Postgres", { region: "us-west2" });
  const postgresVolumeR3Wf = volume("postgres-volume-r3Wf", { alerts: { usage: { "100": {}, "80": {}, "95": {} } }, allowOnlineResize: true, region: "us-west2", sizeMB: 50000 });
  const postgresVolume = volume("postgres-volume", { alerts: { usage: { "100": {}, "80": {}, "95": {} } }, allowOnlineResize: true, region: "us-west2", sizeMB: 50000 });
  const landing = service("landing", {
    source: github("bwscampus/tastetrace", { checkSuites: false, rootDirectory: "/landing" }),
    replicas: { "us-west2": 1 },
    domains: ["tastetrace.app", "www.tastetrace.app"],
  });
  const tastetraceApi = service("tastetrace-api", {
    source: github("bwscampus/tastetrace", { branch: "main", checkSuites: false, rootDirectory: "/api" }),
    build: { buildEnvironment: "V3", builder: "RAILPACK", watchPatterns: ["/api/**"] },
    healthcheck: "/api/health",
    replicas: { "us-west2": 1 },
    env: { ALLOWED_HOSTS: preserve(), APP_NAME: preserve(), DATABASE_URL: preserve(), ENVIRONMENT: preserve(), PASSWORD_RESET_ENABLED: preserve(), PUBLIC_BASE_URL: preserve(), SECRET_KEY: preserve() },
  });
  const tastetrace = service("tastetrace", {
    source: github("bwscampus/tastetrace", { checkSuites: false, rootDirectory: "/app" }),
    healthcheck: "/",
    replicas: { "us-west2": 1 },
    deploy: { preDeployCommand: ["npm run db:push"] },
    domains: ["app.tastetrace.app"],
    env: { DATABASE_URL: preserve(), SESSION_SECRET: preserve() },
  });

  return project("tastetrace", {
    resources: [landing, tastetraceApiDb, Postgres, tastetraceApi, tastetrace, postgresVolumeR3Wf, postgresVolume],
  });
});
