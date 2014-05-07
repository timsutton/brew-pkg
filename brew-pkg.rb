# Builds an OS X installer package from an installed formula.
require 'formula'
require 'optparse'
require 'tmpdir'

module HomebrewArgvExtension extend self
  def with_deps?
    flag? '--with-deps'
  end
end

# cribbed Homebrew module code from brew-unpack.rb
module Homebrew extend self
  def pkg
    unpack_usage = <<-EOS
Usage: brew pkg [--identifier-prefix] [--with-deps] formula

Build an OS X installer package from a formula. It must be already
installed; 'brew pkg' doesn't handle this for you automatically. The
'--identifier-prefix' option is strongly recommended in order to follow
the conventions of OS X installer packages.

Options:
  --identifier-prefix     set a custom identifier prefix to be prepended
                          to the built package's identifier, ie. 'org.nagios'
                          makes a package identifier called 'org.nagios.nrpe'
  --with-deps             include all the package's dependencies in the built package
    EOS

    abort unpack_usage if ARGV.empty?
    identifier_prefix = if ARGV.include? '--identifier-prefix'
      ARGV.next.chomp(".")
    else
      'org.homebrew'
    end

    f = Formula.factory ARGV.last
    # raise FormulaUnspecifiedError if formulae.empty?
    # formulae.each do |f|
    name = f.name
    identifier = identifier_prefix + ".#{name}"
    version = f.version.to_s
    version += "_#{f.revision}" if f.revision.to_s != '0'

    # Make sure it's installed first
    if not f.installed?
      onoe "#{f.name} is not installed. First install it with 'brew install #{f.name}'."
      abort
    end

    # Setup staging dir
    pkg_root = Dir.mktmpdir 'brew-pkg'
    staging_root = pkg_root + HOMEBREW_PREFIX
    ohai "Creating package staging root using Homebrew prefix #{HOMEBREW_PREFIX}"
    FileUtils.mkdir_p staging_root


    pkgs = [f]

    # Add deps if we specified --with-deps
    pkgs += f.recursive_dependencies if ARGV.with_deps?

    pkgs.each do |pkg|
      formula = Formula.factory(pkg.to_s)
      dep_version = formula.version.to_s
      dep_version += "_#{formula.revision}" if formula.revision.to_s != '0'

      ohai "Staging formula #{formula.name}"
      # Get all directories for this keg, rsync to the staging root
      dirs = Pathname.new(File.join(HOMEBREW_CELLAR, formula.name, dep_version)).children.select { |c| c.directory? }.collect { |p| p.to_s }
      dirs.each {|d| safe_system "rsync", "-a", "#{d}", "#{staging_root}/" }

      # Write out a LaunchDaemon plist if we have one
      if formula.plist
        ohai "Plist found at #{formula.plist_name}, staging for /Library/LaunchDaemons/#{formula.plist_name}.plist"
        launch_daemon_dir = File.join staging_root, "Library", "LaunchDaemons"
        FileUtils.mkdir_p launch_daemon_dir
        fd = File.new(File.join(launch_daemon_dir, "#{formula.plist_name}.plist"), "w")
        fd.write formula.plist
        fd.close
      end
    end

    # Build it
    pkgfile = "#{name}-#{version}.pkg"
    ohai "Building package #{pkgfile}"
    safe_system "pkgbuild", \
                "--quiet", \
                "--root", "#{pkg_root}", \
                "--identifier", identifier, \
                "--version", version, \
                "#{pkgfile}"
    FileUtils.rm_rf pkg_root
  end
end

Homebrew.pkg
