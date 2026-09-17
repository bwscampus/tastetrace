import { defineRailway, github, postgres, preserve, project, service, volume } from "railway/iac";

export default defineRailway(() => {
  const Postgres = postgres("Postgres", { region: "us-west2" });
  const postgresVolume = volume("postgres-volume", { alerts: { usage: { "100": {}, "80": {}, "95": {} } }, allowOnlineResize: true, region: "us-west2", sizeMB: 50000 });
  const landing = service("landing", {
    source: github("bwscampus/tastetrace", { checkSuites: false, rootDirectory: "/landing" }),
    replicas: { "us-west2": 1 },
    domains: ["tastetrace.app", "www.tastetrace.app"],
  });
  const tastetrace = service("tastetrace", {
    source: github("bwscampus/tastetrace", { checkSuites: false, rootDirectory: "/app" }),
    healthcheck: "/",
    replicas: { "us-west2": 1 },
    deploy: { preDeployCommand: ["npm run db:push"] },
    domains: ["app.tastetrace.app"],
    env: { DATABASE_URL: preserve(), SESSION_SECRET: preserve() },
  });

  return project("pacific-endurance", {
    resources: [landing, Postgres, tastetrace, postgresVolume],
  });
});
