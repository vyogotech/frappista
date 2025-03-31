# Creating a Basic S2I Builder Image  

## Introduction  

### Why Frappe Framework?  
Frappe Framework is a full-stack web application framework built on Python and JavaScript. It provides a robust foundation for building modern web applications with features like a database abstraction layer, REST API, and a modular architecture. Frappe is widely used for developing ERPNext, a popular open-source ERP solution.  

### Why Use S2I for Development?  
Source-to-Image (S2I) is a powerful tool for building reproducible container images directly from source code. Unlike pre-baked images, S2I allows developers to dynamically inject application source code into a base image, reducing the need for frequent image rebuilds. This approach is particularly beneficial for development workflows, as it accelerates iteration cycles and ensures consistency across environments.  

## Getting Started  

This repo currently aims to build a single node images with all the dependencies for improving the development cycle, ci/cd or quick demos. These images comes with pre-installed site dev.localhost with frappe. So give it a go. 

This solution will help developers to build custom apps quite easily using apps.json or their source code directly. 

### Files and Directories  
| File                   | Required? | Description                                                  |
|------------------------|-----------|--------------------------------------------------------------|
| Containerfile          | Yes       | Defines the base builder image                               |
| s2i/bin/assemble       | Yes       | Script that builds the application                           |
| s2i/bin/usage          | No        | Script that prints the usage of the builder                  |
| s2i/bin/run            | Yes       | Script that runs the application                             |
| s2i/bin/save-artifacts | No        | Script for incremental builds that saves the built artifacts |
| s2i/bin/test           | No        | Script to run tests for the application                      |
| test/run               | No        | Test script for the builder image                            |
| test/test-app          | Yes       | Test application source code                                 |
| Makefile               | No        | Automates build and test commands                            |

#### Containerfile  
Create a *Containerfile* that installs all of the necessary tools and libraries needed to build and run the application. This file will also handle copying the S2I scripts into the created image.  

#### S2I Scripts  

##### assemble  
Create an *assemble* script that will build the application, e.g.:  
- Build Python modules  
- Install Ruby gems  
- Set up application-specific configuration  

The script can also specify a way to restore any saved artifacts from the previous image.  

##### run  
Create a *run* script that will start the application.  

##### save-artifacts (optional)  
Create a *save-artifacts* script which allows a new build to reuse content from a previous version of the application image.  

##### usage (optional)  
Create a *usage* script that will print out instructions on how to use the image.  

##### test (optional)  
Create a *test* script to validate the application functionality after the image is built.  

##### Make the Scripts Executable  
Make sure that all of the scripts are executable by running:  
```
chmod +x s2i/bin/**
```

#### Create the Builder Image  
The following command will create a builder image named `vyogotech/frappe:s2i-base` based on the Containerfile created previously:  
```
docker build -t vyogotech/frappe:s2i-base .
```  
The builder image can also be created using the *make* command if a *Makefile* is included.  

Once the image has finished building, the command `s2i usage vyogotech/frappe:s2i-base` will print out the help info defined in the *usage* script.  


#### Testing the Builder Image  
The builder image can be tested using the following commands:  
```
docker build -t vyogotech/frappe:s2i-base-candidate .
IMAGE_NAME=vyogotech/frappe:s2i-base-candidate test/run
```  
The builder image can also be tested using the *make test* command if a *Makefile* is included.  

#### Creating the Application Image  
The application image combines the builder image with your application's source code, which is served using the application installed via the *Containerfile*, compiled using the *assemble* script, and run using the *run* script.  
The following command will create the application image:  
```
s2i build test/test-app vyogotech/frappe:s2i-base vyogotech/frappe:s2i-base-app
---> Building and installing application from source...
```  
Using the logic defined in the *assemble* script, S2I will now create an application image using the builder image as a base and including the source code from the `test/test-app` directory.  

#### Running the Application Image  
Running the application image is as simple as invoking the `docker run` command:  
```
docker run -d -p 8080:8080 vyogotech/frappe:s2i-base-app
```  
The application, which consists of a simple static web page, should now be accessible at [http://localhost:8080](http://localhost:8080).  

#### Using the Saved Artifacts Script  
Rebuilding the application using the saved artifacts can be accomplished using the following command:  
```
s2i build --incremental=true test/test-app vyogotech/frappe:s2i-base vyogotech/frappe:s2i-base-app
---> Restoring build artifacts...
---> Building and installing application from source...
```  
This will run the *save-artifacts* script, which includes the custom code to back up the currently running application source, rebuild the application image, and then redeploy the previously saved source using the *assemble* script.  


### Advanced Build Options  

In addition to the basic S2I workflow, you can customize the build process using configuration files like `apps.json` and `bench-config.json`. These files allow you to define specific parameters for your Frappe application setup.

#### apps.json  
The `apps.json` file is used to specify the Frappe apps to be installed during the build process. Each app entry should include the app name, repository URL, and branch. For example:  
```json
[
    {
        "name": "erpnext",
        "url": "https://github.com/frappe/erpnext.git",
        "branch": "version-14"
    },
    {
        "name": "custom_app",
        "url": "https://github.com/your-org/custom_app.git",
        "branch": "main"
    }
]
```
During the build, the `assemble` script will read this file and install the specified apps using the `bench get-app` command.

#### bench-config.json  
The `bench-config.json` file defines the configuration for initializing the Frappe bench. It includes details like the branch of the Frappe framework to use and the name of the bench directory. For example:  
```json
{
    "branch": "version-14",
    "bench_name": "frappe-bench"
}
```
The `assemble` script uses this file to initialize the bench with the specified configuration.

#### site-config.json  
The `site-config.json` file is used to define the default site configuration, including the site name and admin password. For example:  
```json
{
    "site_name": "dev.localhost",
    "admin_password": "admin"
}
```
If this file is present, the `assemble` script will create the specified site and configure it with the provided credentials.

#### Example Workflow  
1. Place the `apps.json`, `bench-config.json`, and `site-config.json` files in the appropriate directory.
2. Run the S2I build command:  
   ```
   s2i build test/test-app vyogotech/frappe:s2i-base vyogotech/frappe:s2i-base-app
   ```
3. The `assemble` script will:
   - Initialize the bench using `bench-config.json`.
   - Install the apps listed in `apps.json`.
   - Create the site specified in `site-config.json`.

By using these configuration files, you can automate and customize the build process to suit your specific requirements.
