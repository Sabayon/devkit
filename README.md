# Sabayon devkit

The *Sabayon devkit* is a set of scripts that aims to help developers in various tasks.

You can install it in sabayon with:

`
sudo equo i sabayon-devkit
`

# Building package in a clean environment

Packages can be built in a clean environment with docker by running `sabayon-buildpackages`.

*`sabayon-buildpackages` is just a script wrapper around the `builder` perl script which is placed inside a docker container.*

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

## Build your packages

`sabayon-buildpackages` accepts the same arguments as the builder:


    sabayon-buildpackages app-text/tree
    sabayon-buildpackages plasma-meta --layman kde
    sabayon-buildpackages app-foo/foobar --equo foo-misc/foobar --layman foo --layman bar foo


* --layman foobar -- tells the script to add the "foobar" overlay from layman 
* --equo foo-misc/foobar -- tells the script to install "foo-misc/foobar" before compiling
* The arguments are the packages that you want compile, they can be also in the complete form *e.g. =foo-bar/misc-1.2*


## Folder structure

This is the folder structure that will be automatically created:

`

    myproject/ 
    myproject/portage_artifacts/
    myproject/entropy_artifacts/
    myproject/local_overlay/
`

* myproject/portage\_artifacts/ -- will contain the portage artifacts, they will be consumed in the next steps
* myproject/entropy\_artifacts/ -- will contain the entropy output, our Sabayon repository for the **.tbz2** packages that where in **myproject/portage_artifacts/**
* myproject/local_overlay/ -- is the location of your personal overlay (if necessary)


# Create Sabayon repository from *.tbz2 in a clean environment

You can create Sabayon repositories from packages built with emerge in a clean environment with docker by running `sabayon-createrepo`.

The script will use a docker container to inject packages from  *portage_artifacts/*  in your project folder, the output will be available in *entropy_artifacts/*.

Example:

    sabayon-createrepo

    REPOSITORY_NAME=mytest REPOSITORY_DESCRIPTION="My Wonderful Repository" sabayon-createrepo
    
* REPOSITORY_NAME -- is your repository name id
* REPOSITORY_DESCRIPTION -- is your repository description

