import 'dart:io';

List<int> rawDeflate(List<int> bytes) => ZLibCodec(raw: true).encode(bytes);
List<int> rawInflate(List<int> bytes) => ZLibCodec(raw: true).decode(bytes);
List<int> gzipCompress(List<int> bytes) => GZipCodec().encode(bytes);
List<int> gzipDecompress(List<int> bytes) => GZipCodec().decode(bytes);
const supportsDeflate = true;
