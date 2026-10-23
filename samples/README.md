# Developer Samples: Packaging Custom Apps

This directory contains examples of how to use **Frappista S2I images** to package your own Frappe and ERPNext applications.

## 1. Using S2I directly (Recommended)
You can build a container image for your app without writing a Dockerfile by using the `s2i` tool and providing an `apps.json` file.

### Build Command:
```bash
s2i build . docker.io/vyogo/frappe:s2i-version-15 my-custom-app-image
```

## 2. Using a Containerfile
If you prefer a traditional Docker/Podman build, you can use the Frappista S2I image as a base in your `Containerfile`.

Check out the [sample Containerfile](./custom-app/Containerfile) for an example.

## Configuration Files

- **[apps.json](./custom-app/apps.json)**: Defines the apps to be installed in the bench.
- **[site-config.json](./custom-app/site-config.json)**: (Optional) Provides default site configuration.

## Why use S2I?
- **Standardized Environment**: Uses the same production-ready environment as Frappista.
- **Faster Builds**: Optimized for Frappe/ERPNext app installation and asset building.
- **Multi-Branch Support**: Easily switch between `version-15`, `version-16`, and `develop` by changing the base image tag.
