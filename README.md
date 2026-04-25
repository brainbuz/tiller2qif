# Finance-Tiller2QIF

A utility and library for converting Tiller CSV exports to QIF format for import into other financial software.

## Installation

### From CPAN (recommended after release)

Once released, you can install directly from CPAN:

```sh
cpan Finance::Tiller2QIF
# or
cpanm Finance::Tiller2QIF
```

### From GitHub (development version)

Clone the repository and install manually:

```sh
git clone https://github.com/yourusername/Finance-Tiller2QIF.git
cd Finance-Tiller2QIF
# Install dependencies (if needed)
cpanm --installdeps .
# Build and install
perl Makefile.PL
make
make test
sudo make install
```

## System Perl Dependencies (Packaged)

The following Perl modules are required and available as system packages in most distributions:

- Path::Tiny (Debian/Ubuntu: `libpath-tiny-perl`, RHEL: EPEL or CPAN)
- Text::CSV (Debian/Ubuntu: `libtext-csv-perl`, RHEL: `perl-Text-CSV`)
- DBI (Debian/Ubuntu: `libdbi-perl`, RHEL: `perl-DBI`)
- DateTime::Format::Flexible (Debian/Ubuntu: CPAN, RHEL: CPAN)


On Debian/Ubuntu (including 22.04 and Bookworm):

```sh
sudo apt install libpath-tiny-perl libtext-csv-perl libdbi-perl
sudo cpan DateTime::Format::Flexible
```


On RHEL 9/10 and derivatives:

```sh
sudo dnf install perl-Text-CSV perl-DBI
sudo cpan DateTime::Format::Flexible Path::Tiny
```

For other platforms, install via your package manager or CPAN as needed.

## Usage

    bin/tiller2qif --input my.csv --output out.qif --sqlite state.sqlite3

## Development

- Main script: `bin/tiller2qif`
- Library: `lib/Finance/Tiller2QIF/`
- Tests: `t/`

## License

This software is licensed under the GNU General Public License v3.0 (GPL-3.0).
See the LICENSE file for details.
