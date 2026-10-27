/// Template struk bawaan. Lebar kertas 58 mm = 384 piksel, 80 mm = 576.
const defaultReceiptHtml = '''<style>
  body { font-size: 20px; line-height: 1.3; }
  .tengah { text-align: center; }
  .toko { font-size: 30px; font-weight: bold; }
  .kecil { font-size: 17px; }
  .garis { border-top: 2px solid #000; margin: 8px 0; }
  .baris { display: flex; justify-content: space-between; }
  .item { margin-bottom: 4px; }
  .total { font-size: 28px; font-weight: bold; margin: 4px 0; }
</style>

<div class="tengah">
  {{#logo}}<img src="{{logo}}" style="max-width: 200px"><br>{{/logo}}
  <div class="toko">{{toko.nama}}</div>
  {{#toko.alamat}}<div class="kecil">{{toko.alamat}}</div>{{/toko.alamat}}
</div>

<div class="garis"></div>
{{#retur}}<div class="tengah"><b>NOTA RETUR</b></div>{{/retur}}
<div class="kecil">
  <div class="baris"><span>No</span><span>{{faktur.no}}</span></div>
  {{#retur}}<div class="baris"><span>Retur dari</span><span>{{retur.dari}}</span></div>{{/retur}}
  <div class="baris"><span>{{faktur.tanggal}} {{faktur.jam}}</span><span>{{kasir}}</span></div>
</div>
<div class="garis"></div>

{{#barang}}
<div class="item">
  <div>{{nama}}</div>
  <div class="baris"><span>{{qty}} {{satuan}} x {{harga}}</span><span>{{total}}</span></div>
</div>
{{/barang}}

<div class="garis"></div>
{{#potongan}}
<div class="baris"><span>Subtotal</span><span>{{subtotal}}</span></div>
<div class="baris"><span>{{#voucher}}Voucher {{voucher}}{{/voucher}}{{^voucher}}Potongan{{/voucher}}</span><span>-{{potongan}}</span></div>
{{/potongan}}
<div class="baris total"><span>TOTAL</span><span>{{total}}</span></div>
{{#retur}}
<div class="baris"><span>Dikembalikan ({{metode}})</span><span>{{retur.kembali}}</span></div>
{{#retur.alasan}}<div class="kecil">Alasan: {{retur.alasan}}</div>{{/retur.alasan}}
{{/retur}}
{{^retur}}
{{#tukar}}<div class="baris"><span>Tukar {{tukar.dari}}</span><span>-{{tukar.kredit}}</span></div>{{/tukar}}
{{#pembayaran}}<div class="baris"><span>{{metode}}</span><span>{{jumlah}}</span></div>{{#ref}}<div class="kecil">Ref: {{ref}}</div>{{/ref}}{{/pembayaran}}
{{^pembayaran}}<div class="baris"><span>{{metode}}</span><span>{{bayar}}</span></div>{{/pembayaran}}
{{#kembali}}<div class="baris"><span>Kembali</span><span>{{kembali}}</span></div>{{/kembali}}
{{^pembayaran}}{{#ref}}<div class="kecil">Ref: {{ref}}</div>{{/ref}}{{/pembayaran}}
{{/retur}}
<div class="kecil">{{jumlah_barang}} barang, {{jumlah_item}} item</div>

<div class="garis"></div>
<div class="tengah kecil">
  Terima kasih atas kunjungan Anda<br>
  Barang yang sudah dibeli tidak dapat ditukar/dikembalikan
</div>
{{#cetak_ulang}}<div class="tengah"><b>** CETAK ULANG **</b></div>{{/cetak_ulang}}
''';
