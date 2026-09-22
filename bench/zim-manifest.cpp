// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Jason Titus
//
// zim-manifest — emit a canonical, reader-independent content manifest for a
// ZIM archive, using real libzim.
//
// GPL because it links libzim; lives in zimru-misc for that reason. See
// NOTICE.md for why the repository is version 3 or later.
//
// Why this exists: verifying that zimru's writer preserved an archive's
// content by reading the result back with zimru's own reader proves only
// that the two agree with each other. The obvious neutral reader is
// `zimdump dump` + md5sum over the extracted tree, but that routes every
// path through the filesystem, and real archives contain paths the
// filesystem cannot represent — Korean Wikipedia has entries named "%" and
// "$", on which upstream zimdump aborts with "Error creating symlink" after
// two dozen entries, silently truncating the comparison.
//
// Reading through libzim's API instead touches no filesystem path, so every
// entry is compared regardless of what it is called.
//
// Output: one line per entry, sorted by the caller.
//   <path>\tR\t<target path>          for redirects
//   <path>\tI\t<size>\t<md5 hex>      for items
//
// Usage: zim-manifest <file.zim>
#include <zim/archive.h>
#include <zim/entry.h>
#include <zim/item.h>
#include <zim/blob.h>
#include <openssl/md5.h>

#include <cstdio>
#include <iostream>
#include <string>

int main(int argc, char** argv) {
  if (argc != 2) {
    std::cerr << "usage: " << argv[0] << " <file.zim>\n";
    return 2;
  }
  try {
    zim::Archive archive(argv[1]);
    // iterEfficient walks in cluster order, so each cluster is decompressed
    // once instead of once per entry that happens to live in it. The caller
    // sorts, so the order here only affects speed.
    for (auto entry : archive.iterEfficient()) {
      const std::string path = entry.getPath();
      if (entry.isRedirect()) {
        std::cout << path << "\tR\t" << entry.getRedirectEntry().getPath() << "\n";
        continue;
      }
      auto item = entry.getItem();
      auto blob = item.getData();
      unsigned char digest[MD5_DIGEST_LENGTH];
      MD5(reinterpret_cast<const unsigned char*>(blob.data()), blob.size(), digest);
      char hex[2 * MD5_DIGEST_LENGTH + 1];
      for (int i = 0; i < MD5_DIGEST_LENGTH; i++)
        std::snprintf(hex + 2 * i, 3, "%02x", digest[i]);
      std::cout << path << "\tI\t" << blob.size() << "\t" << hex << "\n";
    }
  } catch (const std::exception& e) {
    std::cerr << "zim-manifest: " << e.what() << "\n";
    return 1;
  }
  return 0;
}
