# Sabayon devkit

The *Sabayon devkit* is a set of scripts that aims to help developers in various tasks.

You can install it in sabayon with:

`
sudo equo i sabayon-devkit
`

## Prerequisites

* docker installed in the machine (`sudo equo i docker`), and the daemon started (`sudo systemctl start docker`)
* if you don't want to run that as root, the user where are you running the script must be in the docker group (`sudo gpasswd -a $USER docker`)

Packages can be built in a clean environment with docker by running `sabayon-buildpackages`.

*`sabayon-buildpackages` and ``sabayon-createrepo are just a script wrapper around the development docker container.*

## Define your workspace

Create a directory to represent your project workspace.



    cd $HOME
    mkdir myproject
    cd myproject


if you plan to make packages from your own ebuilds, and you don't have an overlay published in layman, you can create the `local_overlay` directory and put your overlay tree inside it.



    me@box:myproject/$ mkdir local_overlay


`myproject/local_overlay` is read from the docker container and mounted inside it as the local overlay available in the machine.

If you want, you can define the workspace directory with the variable environment `SAB_WORKSPACE`

`SAB_WORKSPACE=/whatever sabayon-createrepo`


## Folder structure

This is the folder structure of your workspace by default, but you can tweak part of it to your tastes with Environment variables:

`

    myproject/
    myproject/portage_artifacts/
    myproject/entropy_artifacts/
    myproject/local_overlay/
    myproject/specs/
`

* myproject/portage\_artifacts/ -- Created when `sabayon-buildpackages` is started. It contains the portage artifacts, they will be consumed in the next steps
* myproject/entropy\_artifacts/ -- Created when `sabayon-createrepo` is started. It contains the entropy repository files.
* myproject/local_overlay/ -- is the location of your personal overlay (if necessary)
* myproject/specs -- Create it to customize the building process. It can contain custom files for make.conf, uses, envs, masks, unmasks and keywords for package compilation options

the `specs` folder is structured like this and it's merely optional.

as long as you create those files they are used:

- custom.unmask: that's the place for custom unmasks
- custom.mask:  contain your custom masks
- custom.use:  contain your custom use flags
- custom.env:  contain your custom env specifications
- custom.keywords: contain your custom keywords
- make.conf:  it will replace the make.conf on the container with yours.

you can override the Architecture folder in which files are placed specifying in the *SAB_ARCH* environment variable. Default is "intel" (can be *armarch* as for now)

**Note: the portage_artifacts can also contain tbz2 files generated with other methods, if you already have your desired packages already compiled, you can just use `sabayon-createrepo`**

# Building package in a clean environment

`sabayon-buildpackages` accepts the same arguments as the builder:


    sabayon-buildpackages app-text/tree
    sabayon-buildpackages plasma-meta --layman kde
    DOCKER_PULL_IMAGE=1 sabayon-buildpackages app-foo/foobar --equo foo-misc/foobar --layman foo --layman bar foo


* --layman foobar -- tells the script to add the "foobar" overlay from layman
* --equo foo-misc/foobar -- tells the script to install "foo-misc/foobar" before compiling

 Environment variables:
- DOCKER_PULL_IMAGE -- tells the script to update the docker image before compiling, enable it with 1, disable with 0
- OUTPUT_DIR -- optional, default to "portage_artifacts" in your current working directory, it is the path where emerge generated tbz2 are stored (absolute path)
- LOCAL_OVERLAY -- optional, you can specify the path to your local overlay (absolute path)
 The arguments are the packages that you want compile, they can be also in the complete form *e.g. =foo-bar/misc-1.2*


# Create Sabayon repository from \*.tbz2 in a clean environment

You can create Sabayon repositories from packages built with emerge in a clean environment with docker by running `sabayon-createrepo`.

The script will use a docker container to inject packages from  *portage_artifacts/*  in your project folder, the output will be available in *entropy_artifacts/*.

Example:

    sabayon-createrepo

    REPOSITORY_NAME=mytest REPOSITORY_DESCRIPTION="My Wonderful Repository" sabayon-createrepo

* REPOSITORY_NAME -- optional, is your repository name id
* REPOSITORY_DESCRIPTION -- optional, is your repository description
* PORTAGE_ARTIFACTS -- optional if you use the tools in the same dir, you can specify where portage artifacts (\*.tbz2 files) are (absolute path required)
* OUTPUT_DIR -- optional, you can specify where the entropy repository will be stored

You can also put your .tbz2 file externally built inside `entropy_artifacts/` in your workspace folder (you can create it if not already present)  and run `sabayon-createrepo` to generate a repository from them.

In both `sabayon-createrepo` and `sabayon-buildpackages` you can override the docker image used with the environment variable `DOCKER_IMAGE`.
