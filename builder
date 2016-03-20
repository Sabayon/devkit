#!/usr/bin/env perl

use Getopt::Long;
use List::MoreUtils qw(uniq);
use v5.10;

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
my $entropy_repository   = $ENV{ENTROPY_REPOSITORY}   // "main"; # Can be weekly, main, testing
my $artifacts_folder     = $ENV{ARTIFACTS_DIR};
my $dep_scan_depth = $ENV{DEPENDENCY_SCAN_DEPTH} // 2;
my $skip_portage_sync = $ENV{SKIP_PORTAGE_SYNC} // 0;
my $webrsync = $ENV{WEBRSYNC} // 0;

my $make_conf = $ENV{MAKE_CONF};

my @overlays;

GetOptions( 'layman|overlay:s{,}' => \@overlays, 'equo|install:s{,}' => \@equo_install,'equorm|remove:s{,}' => \@equo_remove );

if ( @ARGV == 0 ) {
    help();
    die();
}

$ENV{LC_ALL} = "en_US.UTF-8";    #here be dragons

# A barely print replacement
sub say { print join( "\n", @_ ) . "\n"; }

# Input: package, depth, and atom. Package: sys-fs/foobarfs, Depth: 1 (depth of the package tree) , Atom: 1/0 (enable disable atom output)
sub package_deps {
    my $package = shift;
    my $depth   = shift // 1;  # defaults to 1 level of depthness of the tree
    my $atom    = shift // 0;

    # Since we expect this sub to be called multiple times with the same arguments, cache the results
    state %cache;
    $cache_key = "${package}:${depth}:${atom}";

    if ( ! exists $cache{$cache_key} ) {
        @dependencies = qx/equery -C -q g --depth=$depth $package/;    #depth=0 it's all
        chomp @dependencies;

        # If an unversioned atom is given, equery returns results for all versions in the portage tree
        # leading to duplicates. The sanest thing to do is dedup the list. This gives the superset of all
        # possible dependencies, which isn't perfectly accurate but should be good enough. For completely
        # accurate results, pass in a versioned atom.
        @dependencies = 
          uniq
          sort
          grep { $_ }
          map { $_ =~ s/\[.*\]|\s//g; &atom($_) if $atom; $_ }
          @dependencies;

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
    my $package = shift;
    my $depth = shift;

    my @Installed_Packages = @{+shift};
    my @Available_Packages = @{+shift};

    # Getting the package dependencies and the installed packages
    say "[$package] Getting the package dependencies and the installed packages";
    my @dependencies = package_deps( $package, $depth, 1 );

    my %install_dependencies = map { $_ => 1 } @dependencies;
    # Look for any virtuals and remove its immediate dependencies to avoid
    # installing multiple conflicting packages one by one
    my @virtual_deps;
    for my $dep (@dependencies) {
        push(@virtual_deps, package_deps( $dep, 1, 1 )) if ( $dep =~ /^virtual\// );
    }
    for my $dep (@virtual_deps) {
        $install_dependencies{$dep} = 0 if ( $dep !~ /^virtual\// );
    }
    @dependencies = grep { $install_dependencies{$_} } @dependencies;

    #taking only the 4th column of output as key of the hashmap
    my %installed_packs =
      map { $_ => 1 } @Installed_Packages;
    my %available_packs = map { $_ => 1 } @Available_Packages;

# removing from packages the one that are already installed and keeping only the available in the entropy repositories
    my @to_install = grep( defined $available_packs{$_},
        uniq( grep( !defined $installed_packs{$_}, @dependencies ) ) );
    @to_install=grep { length } @to_install;
    say "[$package] packages that will be installed with equo: @to_install" if @to_install>0;

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
      "";
}

say
"************* IF YOU WANT TO SUPPLY ADDITIONAL ARGS TO EMERGE, pass to docker EMERGE_DEFAULT_OPTS env with your options *************";

if ( @overlays > 0 ) {
    say "Overlay(s) to add";
    foreach my $overlay (@overlays) {
        say "\t- $overlay";
    }
}

say "Installing:";

say "\t* " . $_ for @ARGV;

say "* Syncing stuff for you, if it's the first time, can take a while";

# Syncronizing portage configuration and adding overlays
system("echo 'en_US.UTF-8 UTF-8' > /etc/locale.gen");    #be sure about that.
system(
"cd /etc/portage/;git checkout master; git stash; git pull"
);

if (`uname -m` eq "x86_64\n"){
  system(
  "cd /etc/portage/;rm -rfv make.conf;ln -s make.conf.amd64 make.conf"
  );
}

system("echo 'y' | layman -f -a $_") for @overlays;

my $reponame = "LocalOverlay";

# Setting up a local overlay if doesn't exists
if ( !-f "/usr/local/portage/profiles/repo_name" ) {
    system("mkdir -p /usr/local/portage/{metadata,profiles}");
    system("echo 'LocalOverlay' > /usr/local/portage/profiles/repo_name");
    system("echo 'masters = gentoo' > /usr/local/portage/metadata/layout.conf");
    system("chown -R portage:portage /usr/local/portage");
}
else {
    open FILE, "</usr/local/portage/profiles/repo_name";
    my @FILE = <FILE>;
    close FILE;
    chomp(@FILE);
    $reponame = $FILE[0];
}

qx{
echo '[$reponame]
location = /usr/local/portage
masters = gentoo
priority=9999
auto-sync = no' > /etc/portage/repos.conf/local.conf
};    # Declaring the repo and giving priority

system("mkdir -p /usr/portage/distfiles/git3-src");

unless($skip_portage_sync == 1){
  # sync portage and overlays
  system("layman -S");
  if($webrsync == 1){
   system("emerge-webrsync");
  } else {
   system("emerge --sync");
  }
}

# preparing for MOAR automation
qx|eselect profile set $profile|;
qx{ls /usr/portage/licenses -1 | xargs -0 > /etc/entropy/packages/license.accept}
  ;    #HAHA

if ($use_equo  && $entropy_repository eq "weekly" ) {
  qx|equo repo disable sabayonlinux.org|;
  qx|equo repo enable sabayon-weekly|;
} elsif( $use_equo  &&  $entropy_repository eq "testing") {
  qx|equo repo disable sabayon-weekly|;
  qx|equo repo enable sabayonlinux.org|;
  qx|equo repo enable sabayon-limbo|;
}

if ($use_equo) {
  system("equo repo mirrorsort sabayonlinux.org") if $equo_mirrorsort;
  system("equo up && equo u")
}

system("cp -rf $make_conf /etc/portage/make.conf") if $make_conf;

qx|echo 'ACCEPT_LICENSE="*"' >> /etc/portage/make.conf|;    #just plain evil

my @packages = @ARGV;

if ($use_equo) {
    my @packages_deps;
    my @Installed_Packages = qx/equo q list installed --quiet/;
    my @Available_Packages = available_packages();
    chomp(@Installed_Packages);
    foreach my $p (@packages) {
      say "[$p] Getting the package dependencies which aren't already installed on the system.. ";
        push( @packages_deps, calculate_missing( $p , $dep_scan_depth,\@Installed_Packages,\@Available_Packages) )
          if $equo_install_atoms;
        push( @packages_deps, package_deps( $p, $dep_scan_depth, 0 ) )
          if $equo_install_version;
      say "[$p] Done"
    }
    @packages_deps = grep { defined() and length() } @packages_deps;   #cleaning
    say "", "[install] Installing missing dependencies with equo", @packages_deps, "";
    if ($equo_split_install) {
        system("equo i --bdeps $_") for (@packages_deps,@equo_install);
        if (@equo_remove > 0){
          system("equo rm --nodeps $_") for (@equo_remove);
        }
    }
    else {
        system("equo i --bdeps @packages_deps @equo_install") if ( @packages_deps > 0 or @equo_install > 0);
        system("equo rm --nodeps @equo_remove") if (@equo_remove > 0);
    }
}

say "* Ready to compile, finger crossed";

my $rt = system("emerge $emerge_defaults_args -j $jobs @packages");

my $return = $rt >> 8;

if ($preserved_rebuild) {

    system("emerge -j $jobs --buildpkg \@preserved-rebuild");

}

# Copy files to artifacts folder
system(
    "mkdir -p $artifacts_folder;cp -rfv /usr/portage/packages $artifacts_folder"
) if ( $artifacts_folder and !$return );

exit($return);
