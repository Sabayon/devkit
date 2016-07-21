#!/usr/bin/env perl

use Getopt::Long;
use v5.10;
no feature "say";

my $profile           = $ENV{BUILDER_PROFILE}   // 3;
my $jobs              = $ENV{BUILDER_JOBS}      // 1;
my $use_equo          = $ENV{USE_EQUO}          // 1;
my $preserved_rebuild = $ENV{PRESERVED_REBUILD} // 0;
my $emerge_defaults_args = $ENV{EMERGE_DEFAULTS_ARGS}
  // "--accept-properties=-interactive --verbose --oneshot --complete-graph --buildpkg";
$ENV{FEATURES} = $ENV{FEATURES}
  // "parallel-fetch protect-owned compressdebug splitdebug -userpriv";

my $equo_install_atoms   = $ENV{EQUO_INSTALL_ATOMS}   // 1;
my $equo_install_version = $ENV{EQUO_INSTALL_VERSION} // 0;
my $equo_split_install   = $ENV{EQUO_SPLIT_INSTALL}   // 0;
my $equo_mirrorsort      = $ENV{EQUO_MIRRORSORT}      // 1;
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
my $repoman_check             = $ENV{QA_CHECKS} // 0;

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

sub safe_call {
    my $cmd    = shift;
    my $rt     = system($cmd);
    my $return = $rt >> 8;
    exit($return) if ($rt);
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
    system("mkdir -p /etc/portage/repos.conf/")
      if ( !-d "/etc/portage/repos.conf/" );

    say "==== Adding $reponame ====";
    qx{
echo '[$reponame]
location = /usr/local/overlay/$reponame
sync-type = $sync_type
sync-uri = $repo
auto-sync = yes' > /etc/portage/repos.conf/$reponame.conf
};                            # Declaring the repo and giving priority

    system("emaint sync -r $reponame");
}

# Input: package, depth, and atom. Package: sys-fs/foobarfs, Depth: 1 (depth of the package tree) , Atom: 1/0 (enable disable atom output)
sub package_deps {
    my $package = shift;
    my $depth   = shift // 1;    # defaults to 1 level of depthness of the tree
    my $atom    = shift // 0;

# Since we expect this sub to be called multiple times with the same arguments, cache the results
    state %cache;
    $cache_key = "${package}:${depth}:${atom}";

    if ( !exists $cache{$cache_key} ) {
        @dependencies =
          qx/equery -C -q g --depth=$depth $package/;    #depth=0 it's all
        chomp @dependencies;

# If an unversioned atom is given, equery returns results for all versions in the portage tree
# leading to duplicates. The sanest thing to do is dedup the list. This gives the superset of all
# possible dependencies, which isn't perfectly accurate but should be good enough. For completely
# accurate results, pass in a versioned atom.
        @dependencies = uniq(
            sort
              grep { $_ }
              map { $_ =~ s/\[.*\]|\s//g; &atom($_) if $atom; $_ }
              @dependencies
        );

        $cache{$cache_key} = \@dependencies;
    }

    return @{ $cache{$cache_key} };
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
        say "[$package] Pruning dependencies of virtual packages";
        my %install_dependencies = map { $_ => 1 } @dependencies;

        # Look for any virtuals and remove its immediate dependencies to avoid
        # installing multiple conflicting packages one by one
        my @virtual_deps;
        for my $dep (@dependencies) {
            push( @virtual_deps, package_deps( $dep, 1, 1 ) )
              if ( $dep =~ /^virtual\// );
        }
        for my $dep (@virtual_deps) {
            $install_dependencies{$dep} = 0 if ( $dep !~ /^virtual\// );
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
    @to_install = grep { length } @to_install;
    say "[$package] packages that will be installed with equo: @to_install"
      if @to_install > 0;

    return @to_install;
}

# Input : complete gentoo package (sys-fs/foobarfs-1.9.2)
# Output: atom form (sys-fs/foobarfs)
sub atom { s/-[0-9]{1,}.*$//; }

# Input: Array
# Output: array with unique elements
sub uniq {
    keys %{ { map { $_ => 1 } @_ } };
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

if ( @overlays > 0 ) {
    say "Overlay(s) to add";
    foreach my $overlay (@overlays) {
        say "\t- $overlay";
    }
}

say "[*] Installing:";

say "\t* " . $_ for @ARGV;

say "[*] Syncing configurations files, Layman and Portage";

# Syncronizing portage configuration and adding overlays
system("echo 'en_US.UTF-8 UTF-8' > /etc/locale.gen");    #be sure about that.
system("cd /etc/portage/;git checkout master; git stash; git pull");

system("echo 'y' | layman -f -a $_") for @overlays;

my $reponame = "LocalOverlay";

# Setting up a local overlay if doesn't exists
system(
"rm -rf /usr/local/portage;cp -rf /usr/local/local_portage /usr/local/portage"
) if ( -d "/usr/local/local_portage" );

if ( !-f "/usr/local/portage/profiles/repo_name" ) {
    system("mkdir -p /usr/local/portage/{metadata,profiles}");
    system("echo 'LocalOverlay' > /usr/local/portage/profiles/repo_name");
    system("echo 'masters = gentoo' > /usr/local/portage/metadata/layout.conf");
}
else {
    open FILE, "</usr/local/portage/profiles/repo_name";
    my @FILE = <FILE>;
    close FILE;
    chomp(@FILE);
    $reponame = $FILE[0];
}
system("chown -R portage:portage /usr/local/portage");
system("chmod -R 755 /usr/local/portage");

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
    say "===== Removing overlays: $remove_remote_overlay =====";

    system("layman -d $_") for ( split( / /, $remove_layman_overlay ) );
}
if ( $remove_remote_overlay and $remove_remote_overlay ne "" ) {
    say "===== Removing overlays: $remove_remote_overlay =====";
    system( "rm -rfv /etc/portage/" . $_ . ".conf" )
      for ( split( / /, $remote_overlay ) );
}

system("mkdir -p /usr/portage/distfiles/git3-src");

unless ( $skip_portage_sync == 1 ) {

    # sync portage and overlays
    system("layman -S");
    if ( $webrsync == 1 ) {
        system("emerge-webrsync");
    }
    else {
        system("emerge --sync");
    }
}

# preparing for MOAR automation
qx|eselect profile set $profile|;

if ( $use_equo && $entropy_repository eq "weekly" ) {
    qx|equo repo disable sabayonlinux.org|;
    qx|equo repo enable sabayon-weekly|;
}
elsif ( $use_equo && $entropy_repository eq "testing" ) {
    qx|equo repo disable sabayon-weekly|;
    qx|equo repo enable sabayonlinux.org|;
    qx|equo repo enable sabayon-limbo|;
}

if ($use_equo) {

    say "Devkit version:";
    system("equo s -vq app-misc/sabayon-devkit");

    if ( $enman_repositories and $enman_repositories ne "" ) {
        my @enman_toadd = split( / /, $enman_repositories );
        safe_call("enman add $_") for @enman_toadd;
    }

    if ( $remove_enman_repositories and $remove_enman_repositories ne "" ) {
        my @enman_toremove = split( / /, $remove_enman_repositories );
        system("enman remove $_") for @enman_toremove;
    }

    system("enman add $repository_name")
      if ( $enman_add_self and $repository_name and $repository_name ne "" );
    system("equo repo mirrorsort sabayonlinux.org") if $equo_mirrorsort;
    system("equo up && equo u");
}

system("cp -rf $make_conf /etc/portage/make.conf") if $make_conf;

my @packages          = @ARGV;
my @injected_packages = ();
if ($build_injected_args) {
    @injected_packages = split( / /, $build_injected_args );
}

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
    @packages_deps = grep { defined() and length() } @packages_deps;   #cleaning
    say "", "[install] Those dependencies will be installed with equo :",
      @packages_deps, "";
    if ($equo_split_install) {
        safe_call("equo i $equo_install_args --bdeps $_")
          for ( @packages_deps, @equo_install )
          ; ## bail out here, if installs fails. emerge will compile a LOT of stuff
        if ( @equo_remove > 0 ) {
            system("equo rm --nodeps $_") for (@equo_remove);
        }
    }
    else {
        safe_call(
            "equo i $equo_install_args --bdeps @packages_deps @equo_install")
          if ( @packages_deps > 0 or @equo_install > 0 )
          ; ## bail out here, if installs fails. emerge will compile a LOT of stuff
        system("equo rm --nodeps @equo_remove") if ( @equo_remove > 0 );
    }
}

if ( $repoman_check == 1 ) {
    say "*** Repoman checks ***";
    say "*** QA checks for $_"
      && system(
        "pushd \$(dirname \$(equery which $_ 2>/dev/null)); repoman; popd")
      for ( @packages, @injected_packages );
}

say "*** Ready to compile, finger crossed ***";

system("emerge --info")
  ; #always give detailed information about the building environment, helpful to debug

my $rt;

if ( $emerge_remove and $emerge_remove ne "" ) {
    system("emerge -C $_") for split( / /, $emerge_remove );
}

if ($emerge_split_install) {
    for my $pack (@packages) {
        say "\n" x 2, "==== Compiling $pack ====", "\n" x 2;
        my $tmp_rt = system("emerge $emerge_defaults_args -j $jobs $pack");

#  $rt=$tmp_rt if ($? == -1 or $? & 127 or !$rt); # if one fails, the build should be considered failed!
    }
    $rt = 0;    #consider the build good anyway, like a "keep-going"
}
else {
    $rt = system("emerge $emerge_defaults_args -j $jobs @packages");
}

my $return = $rt >> 8;

# best effort -B
system("emerge $emerge_defaults_args -j $jobs -B $_") for (@injected_packages);

if ($preserved_rebuild) {

    system("emerge -j $jobs --buildpkg \@preserved-rebuild");
    system("revdep-rebuild");

}

# Copy files to artifacts folder
system(
    "mkdir -p $artifacts_folder;cp -rfv /usr/portage/packages $artifacts_folder"
) if ( $artifacts_folder and !$return );

exit($return);
