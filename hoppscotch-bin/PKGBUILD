pkgname=hoppscotch-bin
_tag=26.10.0-0
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
sha256sums=('fc47ad6fb85699d67f995f759382bb78adab5382e1295f0241d2f6b0ec8d58dc')

package() {
  bsdtar -xf data.tar.gz -C "$pkgdir"
}
