import { defineConfig } from "astro/config";
import starlight from "@astrojs/starlight";

export default defineConfig({
  site: "https://open-cluster-foundation.terson.workers.dev",
  integrations: [
    starlight({
      title: "Pyahu OCF",
      description: "Tested building blocks for creating and operating Kubernetes clusters.",
      logo: {
        src: "./src/assets/mark.svg",
        alt: "Pyahu OCF",
        replacesTitle: false
      },
      favicon: "/assets/mark.svg",
      customCss: ["./src/styles/starlight.css"],
      disable404Route: true,
      lastUpdated: true,
      social: [
        {
          icon: "github",
          label: "GitHub",
          href: "https://github.com/pyahu/open-cluster-foundation"
        }
      ],
      sidebar: [
        {
          label: "Start here",
          items: [
            { label: "Getting started", slug: "docs" },
            { label: "CLI and toolchain", slug: "docs/cli" },
            { label: "Architecture", slug: "docs/architecture" }
          ]
        },
        {
          label: "Operations",
          items: [
            { label: "Compatibility", link: "https://github.com/pyahu/open-cluster-foundation/blob/main/docs/compatibility.md" },
            { label: "Lifecycle", link: "https://github.com/pyahu/open-cluster-foundation/blob/main/docs/lifecycle.md" },
            { label: "Production HA", link: "https://github.com/pyahu/open-cluster-foundation/blob/main/docs/production-ha.md" }
          ]
        },
        {
          label: "Reference",
          items: [
            { label: "Components", link: "https://github.com/pyahu/open-cluster-foundation/blob/main/docs/reference/components.md" },
            { label: "Provider contract", link: "https://github.com/pyahu/open-cluster-foundation/blob/main/docs/provider-contract.md" },
            { label: "Design decisions", link: "https://github.com/pyahu/open-cluster-foundation/blob/main/docs/implementation-decisions.md" }
          ]
        }
      ]
    })
  ]
});
