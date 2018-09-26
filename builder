#!/usr/bin/env perl

# Copyright 2016-2018 See AUTHORS file
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program. If not, see <http://www.gnu.org/licenses/>.

use Getopt::Long;
use v5.10;
no feature "say";
use Storable 'dclone';

my $profile              = $ENV{BUILDER_PROFILE} // 16;
my $jobs                 = $ENV{BUILDER_JOBS} // 1;
my $use_equo             = $ENV{USE_EQUO} // 1;
my $preserved_rebuild    = $ENV{PRESERVED_REBUILD} // 0;
my $emerge_defaults_args = $ENV{EMERGE_DEFAULTS_ARGS}
    // "--accept-properties=-interactive --quiet --oneshot --complete-graph --buildpkg";
$ENV{FEATURES} = $ENV{FEATURES}
    // "parallel-fetch protect-owned compressdebug splitdebug -userpriv";

my $equo_install_atoms   = $ENV{EQUO_INSTALL_ATOMS} // 1;
my $equo_install_version = $ENV{EQUO_INSTALL_VERSION} // 0;
my $equo_split_install   = $ENV{EQUO_SPLIT_INSTALL} // 0;
my $equo_mirrorsort      = $ENV{EQUO_MIRRORSORT} // 1;
my $entropy_repository   = $ENV{ENTROPY_REPOSITORY}
    // "main";    # Can be weekly, main, testing
my $artifacts_folder          = $ENV{ARTIFACTS_DIR};
my $dep_scan_depth            = $ENV{DEPENDENCY_SCAN_DEPTH} // 2;
my $skip_portage_sync         = $ENV{SKIP_PORTAGE_SYNC} // 0;
my $emerge_split_install      = $ENV{EMERGE_SPLIT_INSTALL} // 0;
my $webrsync                  = $ENV{WEBRSYNC} // 0;
my $enman_repositories        = $ENV{ENMAN_REPOSITORIES};
my $emerge_remove             = $ENV{EMERGE_REMOVE};
my $remove_enman_repositories = $ENV{REMOVE_ENMAN_REPOSITORIES};
my $remove_remote_overlay     = $ENV{REMOVE_REMOTE_OVERLAY};
my $remove_layman_overlay     = $ENV{REMOVE_LAYMAN_OVERLAY};
my $prune_virtuals            = $ENV{PRUNE_VIRTUALS} // 0;
my $repository_name           = $ENV{REPOSITORY_NAME};
my $enman_add_self            = $ENV{ENMAN_ADD_SELF} // 0;
my $build_injected_args       = $ENV{BUILD_INJECTED_ARGS};
my $equo_masks                = $ENV{EQUO_MASKS};
my $equo_unmasks              = $ENV{EQUO_UNMASKS};
my $equo_install_args         = $ENV{EQUO_INSTALL_ARGS} // "--multifetch=10";
my $remote_overlay            = $ENV{REMOTE_OVERLAY};
my $qualityassurance_checks   = $ENV{QA_CHECKS} // 0;
my $remote_conf_portdir       = $ENV{REMOTE_CONF_PORTDIR};
my $remote_portdir            = $ENV{REMOTE_PORTDIR};
my $pretend                   = $ENV{PRETEND} // 0;
my $obsoleted                 = $ENV{DETECT_OBSOLETE} // 0;
my $target_overlay            = $ENV{TARGET_OVERLAY};
my $verbose                   = $ENV{BUILDER_VERBOSE} // 0;
my $keep_going                = $ENV{KEEP_GOING} // 1;

my $make_conf = $ENV{MAKE_CONF};

my @overlays;
my $help = 0;
GetOptions(
    'layman|overlay:s{,}' => \@overlays,
    'equo|install:s{,}'   => \@equo_install,
    'equorm|remove:s{,}'  => \@equo_remove,
    'help|?'              => \$help
);

help() if $help;

$ENV{LC_ALL}             = "en_US.UTF-8";    #here be dragons
$ENV{ETP_NONINTERACTIVE} = 1;
$ENV{ACCEPT_LICENSE} = "*";    # we can use wildcard since entropy 302

# A barely print replacement
sub say { print join( "\n", @_ ) . "\n"; }

sub loud {
    say;
    say "===" x 4;
    say "===" x 4;
    say @_;
    say "===" x 4;
    say "===" x 4;
    say;
}

sub safe_call {
    my $cmd    = shift;
    my $rt     = _system($cmd);
    my $return = $rt >> 8;
    exit($return) if ($rt);
}

sub _system {
    say "Executing: @_" if $verbose;
    return system(@_);
}

sub append_to_file {
    my ( $file_name, $package ) = @_;

    if ( -f $file_name ) {

        # Check that the package was not already there
        open my $fh_ro, '<:encoding(UTF-8)', $file_name
            or die("Cannot open: $file_name");
        while ( my $line = <$fh_ro> ) {
            return if $line eq $package . "\n";
        }
        close $fh_ro;
    }

    open( my $fh_a, '>>', $file_name )
        or die "Could not open file '$filename' $!";
    print $fh_a $package . "\n";
    close $fh_a;
}

sub parse_overlays {
    map { $_ =~ s/.*?\:\://g; $_ } grep {/\:\:/} @{ dclone( \@_ ) };
}

sub hook_script {
    my $s = shift;
    _system("chmod +x ${s};${s}") if -e $s;
}

sub add_portage_repository {
    my $repo = $_[0];
    my $reponame;
    my $sync_type;
    my @repodef = split( /\|/, $repo );
    ( $reponame, $repo ) = @repodef if ( @repodef == 2 );
    ( $reponame, $sync_type, $repo ) = @repodef if ( @repodef == 3 );

    # try to detect sync-type
    if ( !$sync_type ) {
        $sync_type = ( split( /\:/, $repo ) )[0];
        $sync_type = "git"
            if $repo =~ /github|bitbucket/
            or $sync_type eq "https"
            or $sync_type eq "http";
        $sync_type = "svn" if $repo =~ /\/svn\//;
    }
    $reponame = ( split( /\//, $repo ) )[-1] if !$reponame;
    $reponame =~ s/\.|//g;    #clean
    _system("mkdir -p /etc/portage/repos.conf/")
        if ( !-d "/etc/portage/repos.conf/" );

    say "==== Adding $reponame ====";
    qx{
echo '[$reponame]
location = /usr/local/overlay/$reponame
sync-type = $sync_type
sync-uri = $repo
auto-sync = yes' > /etc/portage/repos.conf/$reponame.conf
};                            # Declaring the repo and giving priority

    _system("emaint sync -r $reponame");
}

# Input: package, depth, and atom. Package: sys-fs/foobarfs, Depth: 1 (depth of the package tree) , Atom: 1/0 (enable disable atom output)
my %package_dep_cache;

sub package_deps {
    my $package = shift;
    my $depth   = shift // 1;   # defaults to 1 level of depthness of the tree
    my $atom    = shift // 0;

# Since we expect this sub to be called multiple times with the same arguments, cache the results
    $cache_key = "${package}:${depth}:${atom}";

    if ( !exists $package_dep_cache{$cache_key} ) {
        my @dependencies =
            qx/equery -C -q g --depth=$depth '$package'/;    #depth=0 it's all
        chomp @dependencies;

# If an unversioned atom is given, equery returns results for all versions in the portage tree
# leading to duplicates. The sanest thing to do is dedup the list. This gives the superset of all
# possible dependencies, which isn't perfectly accurate but should be good enough. For completely
# accurate results, pass in a versioned atom.
        @dependencies = uniq(
            sort
                grep {$_}
                map { $_ =~ s/\[.*\]|\s//g; &abs_atom($_) if $atom; $_ }
                @dependencies
        );

        $package_dep_cache{$cache_key} = \@dependencies;
    }

    return @{ $package_dep_cache{$cache_key} };
}

#Input: nothing
#Output: returns all available packages across all the repository installed in the machine
sub available_packages {
    my @packages;
    my @repos = qx|equo repo list -q|;
    chomp(@repos);
    push( @packages, qx|equo q list available -q $_| ) for @repos;
    chomp(@packages);
    return @packages;
}

# Input: package (sys-fs/foobarfs)
# Output: Array of packages to be installed, that aren't installed in a Sabayon machine
sub calculate_missing {
    my $package            = shift;
    my $depth              = shift;
    my @Installed_Packages = @{ +shift };
    my @Available_Packages = @{ +shift };
    my $prune_virtuals     = shift;

    # Getting the package dependencies and the installed packages
    my @dependencies = package_deps( $package, $depth, 1 );

    if ($prune_virtuals) {
        my %install_dependencies = map { $_ => 1 } @dependencies;

        # Look for any virtuals and remove its immediate dependencies to avoid
        # installing multiple conflicting packages one by one
        my @virtual_deps = ();
        for my $dep (@dependencies) {
            if ( $dep =~ /^virtual\// ) {
                my @child_deps = package_deps( $dep, 1, 1 );
                push( @virtual_deps, @child_deps );
            }
        }

        # Deduplicate the list
        @virtual_deps = uniq(@virtual_deps);

   # Prune the dependencies of the virtual packages from the dependencies list
        for my $dep (@virtual_deps) {
            if ( $dep !~ /^virtual\// ) {
                $install_dependencies{$dep} = 0;
            }
        }
        @dependencies = grep { $install_dependencies{$_} } @dependencies;
    }

    #taking only the 4th column of output as key of the hashmap
    my %installed_packs =
        map { $_ => 1 } @Installed_Packages;
    my %available_packs = map { $_ => 1 } @Available_Packages;

# removing from packages the one that are already installed and keeping only the available in the entropy repositories
    my @to_install = grep( defined $available_packs{$_},
        uniq( grep( !defined $installed_packs{$_}, @dependencies ) ) );
    @to_install = grep {length} @to_install;

    # Strip out the target package from the dependency list
    @to_install = grep { to_atom($_) ne to_atom($package) } @to_install;

    say "[$package] packages that will be installed with equo: @to_install"
        if @to_install > 0;

    return @to_install;
}

sub portage_perms {
    my $dir = shift;
    _system("chown -R portage:portage $dir");
    _system("chmod -R ug+w,a+rX $dir");
}

# Input : complete gentoo package (sys-fs/foobarfs-1.9.2)
# Output: atom form (sys-fs/foobarfs)
sub atom { s/-[0-9]{1,}.*$//; }

sub abs_atom { atom; s/^(\<|\>|=)+// }

# Same again as a function
sub to_atom { my $p = shift; local $_ = $p; atom; return $_; }

sub to_abs_atom { my $p = shift; local $_ = $p; abs_atom; return $_; }

# Input: Array
# Output: array with unique elements
sub uniq {
    keys %{ { map { $_ => 1 } @_ } };
}

# Detect useflags defined as [-alsa,avahi] in atom,
# and fill $hash within the $target sub-hash
sub detect_useflags {
    my ( $target, $packages ) = @_;
    my @packs = @{$packages};
    for my $i ( 0 .. $#packs ) {
        if ( $packages->[$i] =~ /\[(.*?)\]/ ) {
            my $flags = $1;
            $packages->[$i] =~ s/\[.*?\]//g;
            $per_package_useflags->{$target}->[$i] =
                [ +split( /,/, $flags ) ];
        }
    }
}

sub compile_packs {
    my ( $target, @packages ) = @_;
    my $extra_arg;
    my $compiled = {};
    $extra_arg = "-B" if $target eq "injected_targets";
    my $package_counter = 0;
    for my $pack (@packages) {
        my $tmp_rt;
        say "\n" x 2, "==== Compiling $pack ====", "\n" x 2;
        if ( defined $per_package_useflags->{$target}->[$package_counter]
            and @{ $per_package_useflags->{$target}->[$package_counter] }
            > 0 )
        {
            say "USEFLAGS: "
                . join( " ",
                @{ $per_package_useflags->{$target}->[$package_counter] } );
            $tmp_rt = _system(
                "USE=\""
                    . join(
                    " ",
                    @{  $per_package_useflags->{$target}->[$package_counter]
                    }
                    )
                    . "\" emerge $emerge_defaults_args -j $jobs $extra_arg '$pack'"
            );
        }
        else {
            $tmp_rt =
                _system(
                "emerge $emerge_defaults_args -j $jobs $extra_arg '$pack'");
        }
        $package_counter++;
        $compiled->{$pack} = $tmp_rt;
    }
    return $compiled;
}

sub help {
    say "-> You should feed me with something", "", "Examples:", "",
        "\t$0 app-text/tree", "\t$0 plasma-meta --layman kde", "",
        "\t$0 app-foo/foobar --equo foo-misc/foobar --equo net-foo/foobar --layman foo --layman bar foo",
        "**************************", "",
        "You can supply multiple overlays as well: $0 plasma-meta --layman kde plab",
        "The documentation is available at https://github.com/Sabayon/devkit",
        "";
    exit 0;
}

say "****************************************************";

my $per_package_useflags;
my @packages = @ARGV;
my @injected_packages =
    $build_injected_args ? split( / /, $build_injected_args ) : ();
my @parsed_overlays =
    grep { $_ !~ /gentoo/i } parse_overlays( @packages, @injected_packages );

say "Detected overlays: @parsed_overlays" if @parsed_overlays;

@overlays = uniq( @overlays, @parsed_overlays );

if ( @overlays > 0 ) {
    say "Overlay(s) to add";
    foreach my $overlay (@overlays) {
        say "\t- $overlay";
    }
}

say "[*] Compiling:";

say "\t* " . $_ for @ARGV;

loud "Setup phase start";

if ($pretend) {
    say "[*] PRETEND enabled, no real action will be performed.";
    say "    Bear in mind that in such way the list of packages";
    say "    that emerge will try to compile will be bigger";
    $equo_install_args    .= " -p";
    $emerge_defaults_args .= " -p";
}

# Syncronizing portage configuration and adding overlays
system("echo 'en_US.UTF-8 UTF-8' > /etc/locale.gen");    #be sure about that.

# If defined, fetch a remote /etc/portage
if ( $remote_conf_portdir ne "" ) {
    _system("rm -rf /etc/portage");
    _system("git clone $remote_conf_portdir /etc/portage");
    portage_perms('/etc/portage');
}
else {
    _system("cd /etc/portage/;git checkout master; git stash; git pull");
}

# If defined, fetch a remote /usr/portage
if ( $remote_portdir ne "" ) {
    _system("rm -rf /usr/portage");
    _system("git clone $remote_portdir /usr/portage");
}

_system("mkdir /var/lib/layman") if ( !-d "/var/lib/layman" );
_system("touch /var/lib/layman/make.conf && layman-updater -R")
    if ( !-e "/var/lib/layman/make.conf" );

_system("echo 'y' | layman -f -a $_") for @overlays;

my $reponame = "LocalOverlay";

# Setting up a local overlay if doesn't exists
_system(
    "rm -rf /usr/local/portage;cp -rf /usr/local/local_portage /usr/local/portage"
) if ( -d "/usr/local/local_portage" );

if ( !-f "/usr/local/portage/profiles/repo_name" ) {
    _system("mkdir -p /usr/local/portage/{metadata,profiles}");
    _system("echo 'LocalOverlay' > /usr/local/portage/profiles/repo_name");
    _system(
        "echo 'masters = gentoo' > /usr/local/portage/metadata/layout.conf");
}
else {
    open FILE, "</usr/local/portage/profiles/repo_name";
    my @FILE = <FILE>;
    close FILE;
    chomp(@FILE);
    $reponame = $FILE[0];
}
portage_perms('/usr/local/portage');

qx{
echo '[$reponame]
location = /usr/local/portage
masters = gentoo
priority=9999
auto-sync = no' > /etc/portage/repos.conf/local.conf
};    # Declaring the repo and giving priority

if ( $remote_overlay and $remote_overlay ne "" ) {
    add_portage_repository($_) for ( split( / /, $remote_overlay ) );
}

if ( $remove_layman_overlay and $remove_layman_overlay ne "" ) {
    say "===== Removing overlays: $remove_layman_overlay =====";

    _system("layman -d $_") for ( split( / /, $remove_layman_overlay ) );
}
if ( $remove_remote_overlay and $remove_remote_overlay ne "" ) {
    say "===== Removing overlays: $remove_remote_overlay =====";
    _system( "rm -rfv /etc/portage/" . $_ . ".conf" )
        for ( split( / /, $remote_overlay ) );
}

_system("mkdir -p /usr/portage/distfiles/git3-src");
portage_perms('/usr/portage');

unless ( $skip_portage_sync == 1 ) {

    # sync portage and overlays
    _system("layman -S");
    if ( $webrsync == 1 ) {
        _system("emerge-webrsync");
    }
    else {
        _system("emerge --sync --quiet");
    }
}

# preparing for MOAR automation
say "Setting new profile to $profile"   if defined $profile;
_system("eselect profile set $profile") if defined $profile;
_system("eselect profile list")         if defined $profile;

if ( $use_equo && $entropy_repository eq "weekly" ) {
    _system("equo repo disable sabayonlinux.org");
    _system("equo repo enable sabayon-weekly");
}
elsif ( $use_equo && $entropy_repository eq "testing" ) {
    _system("equo repo disable sabayon-weekly");
    _system("equo repo enable sabayonlinux.org");
    _system("equo repo enable sabayon-limbo");
}

if ($use_equo) {

    say "Devkit version:";
    _system("equo s -vq app-misc/sabayon-devkit");

    _system("equo repo mirrorsort sabayonlinux.org") if $equo_mirrorsort;

    # Try to use last enman version
    _system("equo up && equo i enman --relaxed");

    _system("enman list --installed -q");
    my $enman_list_output = qx|enman list --installed -q|;
    chomp($enman_list_output);
    my @installed_enman_repos;

    if ( $enman_list_output eq "No repositories were installed with enman" ) {
        @installed_enman_repos = ();
    }
    else {
        @installed_enman_repos = split( / /, $enman_list_output );
    }

    if ( $enman_repositories and $enman_repositories ne "" ) {
        say "==================================";
        my @enman_toadd;
        if ( index( $enman_repositories, "\n" ) != -1 ) {
            @enman_toadd = split( /\n/, $enman_repositories );
        }
        else {
            @enman_toadd = split( / /, $enman_repositories );
        }

        for my $enman_add (@enman_toadd) {
            say "Check enman " . $enman_add;
            if ( !grep ( $enman_add, @installed_enman_repos ) ) {
                say "Try to install " . $enman_add;
                _system("enman add $enman_add");
            }
            else {
                say "Already present: " . $enman_add;
            }
        }
        say "==================================";
    }

    if ( $remove_enman_repositories and $remove_enman_repositories ne "" ) {
        say "==================================";
        my @enman_toremove;
        if ( index( $remove_enman_repositories, "\n" ) != -1 ) {
            @enman_toremove = split( /\n/, $remove_enman_repositories );
        }
        else {
            @enman_toremove = split( / /, $remove_enman_repositories );
        }

        for my $enman_remove (@enman_toremove) {
            if ( grep ( $enman_remove, @installed_enman_repos ) ) {
                say "Try to remove enamn repository " . $enman_remove;
                _system("enman remove $enman_remove");
            }
            else {
                say "Enman repository $enman_remove is not present.";
            }
        }
        say "==================================";
    }

    _system("enman add $repository_name")
        if ($enman_add_self
        and $repository_name
        and $repository_name ne "" );

    _system("equo up && equo u");
}

_system("cp -rf $make_conf /etc/portage/make.conf") if $make_conf;

if (@injected_packages) {
    say "[*] Injected installs:";
    say "\t* " . $_ for @injected_packages;
}

# Allow users to specify atoms as: media-tv/kodi[-alsa,avahi]
if ($emerge_split_install)
{    # For targets this will be available only if split_install is enabled
    detect_useflags( "targets", \@packages );
}
else {
    map { $_ =~ s/\[.*?\]//g; $_; }
        @packages
        ; # Clean up [] if user didn't specified split_install, but specified a useflag combination
}
detect_useflags( "injected_targets", \@injected_packages );

if ($use_equo) {

    # best effort mask
    if ($equo_masks) {
        append_to_file( "/etc/entropy/packages/package.mask", $_ )
            for ( split( / /, $equo_masks ) );
    }

    # best effort unmask
    if ($equo_unmasks) {
        append_to_file( "/etc/entropy/packages/package.unmask", $_ )
            for ( split( / /, $equo_unmasks ) );
    }

    my @packages_deps;
    my @Installed_Packages = qx/equo q list installed --quiet/;
    my @Available_Packages = available_packages();
    chomp(@Installed_Packages);

    my %installed_packs =
        map { $_ => 1 } @Installed_Packages;

# Remove any already installed packages from the list of entropy packages to install in the build spec
    @equo_install = grep { !exists $installed_packs{$_} } @equo_install;

    foreach my $p (@packages) {
        say
            "[$p] Getting the package dependencies which aren't already installed on the system.. ";
        push(
            @packages_deps,
            calculate_missing(
                $p,                   $dep_scan_depth,
                \@Installed_Packages, \@Available_Packages,
                $prune_virtuals
            )
        ) if $equo_install_atoms;
        push( @packages_deps, package_deps( $p, $dep_scan_depth, 0 ) )
            if $equo_install_version;
    }
    @packages_deps = grep { defined() and length() } @packages_deps; #cleaning
    say "", "[install] Those dependencies will be installed with equo :",
        @packages_deps, "";
    if ($equo_split_install) {
        _system("equo i $equo_install_args --bdeps '$_'")
            for ( @packages_deps, @equo_install )
            ; ## bail out here, if installs fails. emerge will compile a LOT of stuff
        if ( @equo_remove > 0 and !$pretend ) {
            say "Removing with equo: @equo_remove";
            _system("equo rm --nodeps '$_'") for (@equo_remove);
        }
    }
    else {
        my @p = map {"'$_'"} ( @packages_deps, @equo_install );
        my @r = map {"'$_'"} @equo_remove;
        _system("equo i $equo_install_args --bdeps @p")
            if ( @p > 0 )
            ; ## bail out here, if installs fails. emerge will compile a LOT of stuff
        _system("equo rm --nodeps @r") if ( @r > 0 );
    }
}

loud "Pre-compilation phase start";

_system("emerge --info")
    ; #always give detailed information about the building environment, helpful to debug

if ( $emerge_remove and $emerge_remove ne "" ) {
    say "Removing with emerge: $emerge_remove";
    _system("emerge -C '$_'") for split( / /, $emerge_remove );
}

hook_script("./pre-script");
hook_script("/pre-script");

loud "Compilation phase start";

my $return = 0;
if ($emerge_split_install) {
    my $res = compile_packs( "targets", @packages );
    loud "Compilation summary";
    foreach my $k ( keys %{$res} ) {
        my $c = $res->{$k} >> 8;
        if ( $c != 0 ) {
            say "$k : build failed ( Exit: $c )";
            $return = 1 unless $keep_going;
        }
        else {
            say "$k : build succeeded";
        }
    }
}
else {
    my @p = map {"'$_'"} @packages;
    my $rt = _system("emerge $emerge_defaults_args -j $jobs @p");
    $return = $rt >> 8;
}

if ( @injected_packages > 0 ) {
    my $res = compile_packs( "injected_targets", @injected_packages );
    loud "Compilation summary for injected_targets";
    foreach my $k ( keys %{$res} ) {
        my $c = $res->{$k} >> 8;
        if ( $c != 0 ) {
            say "$k : build failed ( Exit: $c )";
            $return = 1 unless $keep_going;
        }
        else {
            say "$k : build succeeded";
        }
    }
}

loud "Compilation phase end (Exit: $return)";

hook_script("./post-script");
hook_script("/post-script");

if ( $preserved_rebuild and !$pretend ) {

    _system("emerge -j $jobs --buildpkg \@preserved-rebuild");
    _system("revdep-rebuild");

}

if ( $qualityassurance_checks == 1 ) {
    loud "Quality assurance checks";
    foreach my $pn ( map { abs_atom; $_ } ( @packages, @injected_packages ) )
    {
        say ">> Running repoman on $pn";
        _system(
            "pushd \$(dirname \$(equery which '$pn' 2>/dev/null)); repoman; popd"
        );
        $pn =~ s/\:\:.*//g;
        say ">> Detecting missing dependencies for $pn";
        _system("dynlink-scanner '$pn'");
        _system("depcheck '$pn'");
    }
}

if ( $obsoleted and $target_overlay ) {
    loud "Obsoletes detection";
    _system("sabayon-detectobsolete --overlay ${target_overlay}");
}

# Copy files to artifacts folder
system(
    "mkdir -p $artifacts_folder;cp -rfv /usr/portage/packages $artifacts_folder"
) if ( $artifacts_folder and !$return and !$pretend );

exit($return);
