
# Scripts

Devkit contains a list of scripts used by Sabayon for building process and
for manage package injection to repositories.

## List of files


  * `depcheck`: a tool to report both undeclared and potentially-unused
     runtime dependencies.

  * `dynlink-scanner`: a tool for retrieve list of linked libraries used
     by a package. Use try_dlopen execute binary.

  * `sabayon-brokenlibs`: a tool for retrieve list of all dependencies
     of a binary through equo and equery tools. Print list of dependencies.
     This script depends on:
       - equo
       - equery
       - sabayondevkit-functions.sh

  * `sabayon-buildpackages`: Script for Spawning the package builder container.
     This script depends on:
       - sabayondevkit-functions.sh

  * `sabayon-bz2brokenlibs`: Unpack bz2 tarball and execute sabayon-brokenlibs
     to every files unpacked.
     This script depends on:
       - sabayondevkit-functions.sh

  * `sabayon-createrepo`: Script for spawning container for commit packages to
     a repository and create it if doesn't exists.
     This script depends on:
       - sabayondevkit-functions.sh

  * `sabayon-createrepo-cleanup`: Script for spawning container for cleanup
     expired packages from a repository.
     This script depends on:
       - sabayondevkit-functions.sh

  * `sabayon-createrepo-remove`: Script for spawning container for remove a list
     of packages from a repository.
     This script depends on:
       - sabayondevkit-functions.sh

  * `sabayon-detectobsolete`: Perl script for found obsolete packages in an
    overlay. Possible options are: --arch, --overlay and --verbose.
    This script depends on:
       - querypkg

  * `sabayon-entropypreservedlibs`: Perl script for retrieve list of packages that has
     dependencies to old libraries.
     See also [here](https://wiki.sabayon.org/index.php?title=En:Sabayon_Devkit#sabayon-entropypreservedlibs)

  * `sabayon-help-info`: Bash script for grabbing system information and post to
     sabayon pastebin.
     This script depends on:
       - pastebunz

  * `sabayon-maint-helper`: Script for builder boxes maintenance.
     Possible options are:
       - `--installed`: For upgrades all the packages installed in the box.
       - `--obsolete`: Upgrade ONLY the packages that are listed obsolete
       - `--all`: Tries to upgrade all packages
       - `--category`: Tries to upgrade/install all packages present in a specified category.
     This script depends on:
       - sabayondevkit-functions.sh

  * `sabayon-tbz2extract`: Python script for extract tbz2 package.

  * `sabayon-tbz2truncate`: Python script for truncate tbz2 package

  * `sabayon-xpakextract`: Python script for convert tbz2 in .xpak file

  * `builder`: Perl script for build packages.

## Scripts Variables

### sabayon-createrepo

| Env Variable | Default | Description |
|--------------|---------|-------------|
| SAB_WORKSPACE | $PWD | Workspace directory |
| REPOSITORY_NAME | default | Name of the repository to create. |
| REPOSITORY_DESCRIPTION | My Sabayon repository | Description of the repository to create. |
| DOCKER_IMAGE | sabayon/eit-amd64 | Docker image to use on create repository |
| PORTAGE_ARTIFACTS | $SAB_WORKSPACE/portage_artifacts | Directory of the artifacts to insert on repository |
| OUTPUT_DIR | $SAB_WORKSPACE/entropy_artifacts | Output directory of the repository |
| DOCKER_OPTS | --ti --rm | Docker options to pass on run container. |
| PUBKEY | - | Define file to mount as volume to /etc/entropy/mykeys/key.pub |
| PRIVATEKEY | - | Define file to mount as volume to /etc/entropy/mykeys/private.key |

### sabayon-createrepo-cleanup

| Env Variable | Default | Description |
|--------------|---------|-------------|
| SAB_WORKSPACE | $PWD | Workspace directory |
| REPOSITORY_NAME | default | Name of the repository to clean. |
| REPOSITORY_DESCRIPTION | My Sabayon repository | Description of the repository to clean. |
| DOCKER_IMAGE | sabayon/eit-amd64 | Docker image to use on clean repository |
| OUTPUT_DIR | $SAB_WORKSPACE/entropy_artifacts | Directory of the repository |
| DOCKER_OPTS | --ti --rm | Docker options to pass on run container. |
| PUBKEY | - | Define file to mount as volume to /etc/entropy/mykeys/key.pub |
| PRIVATEKEY | - | Define file to mount as volume to /etc/entropy/mykeys/private.key |

### sabayon-createrepo-remove

| Env Variable | Default | Description |
|--------------|---------|-------------|
| SAB_WORKSPACE | $PWD | Workspace directory |
| REPOSITORY_NAME | default | Name of the repository where remove packages. |
| REPOSITORY_DESCRIPTION | My Sabayon repository | Description of the repository. |
| DOCKER_IMAGE | sabayon/eit-amd64 | Docker image to use on clean repository |
| OUTPUT_DIR | $SAB_WORKSPACE/entropy_artifacts | Directory of the repository |
| DOCKER_OPTS | --ti --rm | Docker options to pass on run container. |
| PUBKEY | - | Define file to mount as volume to /etc/entropy/mykeys/key.pub |
| PRIVATEKEY | - | Define file to mount as volume to /etc/entropy/mykeys/private.key |

### sabayon-buildpackages

| Env Variable | Default | Description |
|--------------|---------|-------------|
| SAB_WORKSPACE | $PWD | Workspace directory |
| DOCKER_IMAGE | sabayon/builder-amd64 | Docker image to use for compilation |
| SAB_ARCH | intel | Name of arch to use defined on build Sabayon project |
| DOCKER_PULL_IMAGE | 0 | If try to pull last image (1) or use local version |
| MAKE_CONF | $SAB_WORKSPACE/specs/make.conf | Path of make.conf custom to supply on compilation |
| OUTPUT_DIR | $SAB_WORKSPACE/portage_artifacts/ | Where are written portage artifacts compiled |
| LOCAL_OVERLAY | $SAB_WORKSPACE/local_overlay/ | Directory to use for supply local overlay as volume of the image on compilation |
| ENTROPY_REPOSITORY | main | Sabayon repository to use: weekly, main or testing |
| DOCKER_OPTS | --ti --rm --cap-add=SYS_PTRACE | Options to use on running Docker image |
| PORTAGE_CACHE | - | If present permit to supply host portage directory to container |
| BUILDER_PROFILE | - | Permit to choice Gentoo Profile to use |
| EMERGE_SPLIT_INSTALL | - | Possible values are 0/1. |
| BUILDER_JOBS | 1 | Define number of jobs for emerge phase. |
| USE_EQUO | 1 | Use equo for install and align compilation environment. |
| PRESERVED_REBUILD | 0 | Execute (emerge @preserve-rebuild) |
| EQUO_INSTALL_ATOMS | 1 | Try to install existing dependencies from equo repositories |
| DEPENDENCY_SCAN_DEPTH | 2 | Define depth level for dependencies calculation |
| FEATURES | "parallel-fetch protect-owned compressdebug splitdebug -userpriv" | Override Gentoo FEATURES variable |
| EMERGE_DEFAULTS_ARGS |  "--accept-properties=-interactive --verbose --oneshot --complete-graph --buildpkg" | Override default emerge options |
| EQUO_INSTALL_VERSION | 0 | |
| EQUO_SPLIT_INSTALL | 0 | |
| ARTIFACTS_DIR | - | Additional directory where copy artifacts |
| ENTROPY_REPOSITORY | main | Choice repository to use. Values: main, weekly, testing |
| SKIP_PORTAGE_SYNC | 0 | Skip portage sync before compilation |
| EQUO_MIRRORSORT | 1 | Execute equo mirrorsort before compilation |
| WEBRSYNC | 0 | Use webrsync instead of defult rsync |
| ENMAN_REPOSITORIES | - | Define list of enman repositories to add |
| REMOVE_ENMAN_REPOSITORIES | - | Define list of enman repositories to remove |
| DISTFILES | - | Permit to mount volume to /usr/portage/distfiles directory and speedup download phase if packages are already available |
| INTERNAL_BUILDER | - | Define a host builder to use instead of docker builder binary |
| ENTROPY_DOWNLOADED_PACKAGES | - | Mount volume to /var/lib/entropy/client/packages to use caching on download equo packages |
| DISTCC_HOSTS | - | Override Gentoo DISTCC_HOSTS variable to use DISTCC |
| PRUNE_VIRTUALS | 0 | Prune virtuals packages to avoid conflicts. |
| REPOSITORY_NAME | - | Add single enman repository (for compilation of scr repository itself) |
| ENMAN_ADD_SELF | 0 | If add with enman repository define on REPOSITORY_NAME variable |
| EQUO_MASKS | - | Define a list of packages to mask with equo mask command |
| EQUO_UNMASKS | - | Define a list of packages to unmask with equo unmask command |
| EMERGE_REMOVE | - | Define a list of packages to remove with emerge -C command before compilation |
| REMOTE_OVERLAY | - | Define a list of overlay to add before compilation |
| REMOVE_LAYMAN_OVERLAY | - | Define a list of overlays to remove before compilation |
| REMOTE_REMOTE_OVERLAY | - | Define a list of files under /etc/portage to remove |
| QA_CHECKS | - | Execute quality check on packages. repoman, dynlink-scanner and depcheck |
| REMOTE_CONF_PORTDIR | - | If defined permit to define a git repository to clone under /etc/portage directory. |
| REMOTE_PORTDIR | - | If defined permit to define a git repository to clone under /usr/portage directory. |
| ETP_NOCACHE | - | Define ETP_NOCACHE variable on environment |
| PRETEND | 0 | If set to 1 append -p option to emerge commands. |
| BUILDER_VERBOSE | 0 | If set to 1 add verbose to builder program. |
| DETECT_OBSOLETE | 0 | Execute script sabayon-detectobsolete to target overlay to found obsolete ebuilds. |
| TARGET_OVERLAY | - | Define overlay where execute sabayon-detectobsolete script. Require DETECT_OBSOLETE variable set to 1. |
| LOCAL_OVERLAY | - | Define a directory to mount as volume to /usr/local/local_portage |
| SHARE_WORKSPACE | - | If defined mount volume defined on SAB_WORKSPACE variable to /devkit-workspace |
| PRE_SCRIPT | - | Mount a custom script to /pre-script execute before compilation |
| POST_SCRIPT | - | Mount a custom script to /post-script execute after packages compilation |
| MAKE_CONF | - | If defined mount defined file to /etc/portage/make.conf.custom and define variable MAKE_CONF to bet to mounted path. |

