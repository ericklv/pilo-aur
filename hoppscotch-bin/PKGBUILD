pkgname=hoppscotch-bin
_tag=26.10.1-0
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
sha256sums=('8a5d2c020700b4c0e9307725b2e39f685bbf3f29e7c874e6ef2f83c813eecb38')

package() {
  bsdtar -xf data.tar.gz -C "$pkgdir"
}
