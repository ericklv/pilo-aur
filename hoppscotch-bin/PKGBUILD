pkgname=hoppscotch-bin
_tag=26.9.0-0
pkgver=${_tag//-/.}
pkgrel=1
pkgdesc="Desktop App for hoppscotch.io"
arch=('x86_64')
url="https://hoppscotch.io"
license=('MIT')
depends=('webkit2gtk-4.1' 'gtk3')
provides=('hoppscotch')
conflicts=('hoppscotch')
options=('!strip' '!debug')
source=("https://github.com/hoppscotch/releases/releases/download/v$_tag/Hoppscotch_linux_x64.deb")
sha256sums=('1804cf1fdae3b9f5546e82f171c3f63045b3378253c1300700ab6695779ad569')

package() {
  bsdtar -xf data.tar.gz -C "$pkgdir"
}
