// SPDX-License-Identifier: GPL-3.0-or-later
//
// Derived from zim-tools (https://github.com/openzim/zim-tools):
//   src/zimrecreate.cpp          main(), the recreate loop
//     Copyright (C) 2019-2020 Matthieu Gautier <mgautier@kymeria.fr>
//   src/tools.h, src/tools.cpp   CopyItem, ItemProvider, guess_is_front_article
//     Copyright 2013-2016 Emmanuel Engelhart <kelson@kiwix.org>
//     Copyright 2016 Matthieu Gautier <mgautier@kymeria.fr>
// Modifications for this benchmark harness: Copyright (C) 2026 Jason Titus.
//
// The upstream notice, which also governs this file:
//
//   This program is free software; you can redistribute it and/or modify
//   it under the terms of the GNU  General Public License as published by
//   the Free Software Foundation; either version 3 of the License, or
//   any later version.
//
//   This program is distributed in the hope that it will be useful,
//   but WITHOUT ANY WARRANTY; without even the implied warranty of
//   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
//   GNU General Public License for more details.
//
//   You should have received a copy of the GNU General Public License
//   along with this program; if not, write to the Free Software
//   Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston,
//   MA 02110-1301, USA.
//
// Faithful re-implementation of zim-tools `zimrecreate` (new-namespace path)
// driving libzim's built-in Xapian fulltext+title indexer via
// configIndexing(true,"eng"). This is the "old fashioned libzim way" of
// ZIM indexing+building, used as the benchmark baseline against zimru+xapianbuilder.
//
// Mirrors zim-tools src/zimrecreate.cpp + the CopyItem/ItemProvider helpers
// from src/tools.h, restricted to archives that use the new namespace scheme
// (all streetzim ZIMs do).
#include <iostream>
#include <memory>
#include <string>
#include <zim/archive.h>
#include <zim/item.h>
#include <zim/blob.h>
#include <zim/writer/creator.h>
#include <zim/writer/contentProvider.h>
#include <zim/writer/item.h>

static bool guess_is_front_article(const std::string& mimetype) {
  return ( mimetype.find("text/html") == 0
        && mimetype.find("raw=true") == std::string::npos);
}

class ItemProvider : public zim::writer::ContentProvider {
    zim::Item item;
    bool feeded;
  public:
    explicit ItemProvider(zim::Item item) : item(item), feeded(false) {}
    zim::size_type getSize() const override { return item.getSize(); }
    zim::Blob feed() override {
      if (feeded) return zim::Blob();
      feeded = true;
      return item.getData();
    }
};

class CopyItem : public zim::writer::Item {
    zim::Item item;
  public:
    explicit CopyItem(const zim::Item item) : item(item) {}
    std::string getPath() const override { return item.getPath(); }
    std::string getTitle() const override { return item.getTitle(); }
    std::string getMimeType() const override { return item.getMimetype(); }
    std::unique_ptr<zim::writer::ContentProvider> getContentProvider() const override {
      return std::unique_ptr<zim::writer::ContentProvider>(new ItemProvider(item));
    }
    zim::writer::Hints getHints() const override {
      return { { zim::writer::HintKeys::FRONT_ARTICLE, guess_is_front_article(item.getMimetype()) } };
    }
};

int main(int argc, char** argv) {
  if (argc < 3) {
    std::cerr << "usage: " << argv[0]
              << " ORIGIN OUT [nbWorkers=4] [clusterBytes=2097152] [ft=1]\n";
    return 2;
  }
  std::string originFilename = argv[1];
  std::string outFilename    = argv[2];
  unsigned long nbThreads = (argc > 3) ? std::stoul(argv[3]) : 4;
  zim::size_type clusterSize = (argc > 4) ? std::stoull(argv[4]) : 2048*1024;
  bool withFt = (argc > 5) ? (std::string(argv[5]) != "0") : true;

  zim::Archive origin(originFilename);
  if (!origin.hasNewNamespaceScheme()) {
    std::cerr << "ERROR: this harness only handles new-namespace ZIMs\n";
    return 3;
  }

  zim::writer::Creator creator;
  creator.configVerbose(false)
         .configIndexing(withFt, "eng")
         .configClusterSize(clusterSize)
         .configNbWorkers(nbThreads);

  creator.startZimCreation(outFilename);

  try {
    creator.setMainPath(origin.getMainEntry().getItem(true).getPath());
  } catch(...) {}

  try {
    auto illustration = origin.getIllustrationItem();
    creator.addIllustration(48, illustration.getData());
  } catch(...) {}

  for (auto& metakey : origin.getMetadataKeys()) {
    if (metakey == "Counter" || metakey.find("Illustration_") == 0) continue;
    auto metadata = origin.getMetadata(metakey);
    creator.addMetadata(metakey,
        std::unique_ptr<zim::writer::ContentProvider>(new zim::writer::StringProvider(metadata)),
        "text/plain");
  }

  for (auto& entry : origin.iterEfficient()) {
    if (entry.isRedirect()) {
      creator.addRedirection(entry.getPath(), entry.getTitle(),
                             entry.getRedirectEntry().getPath(),
                             {{zim::writer::HintKeys::FRONT_ARTICLE, 1}});
    } else {
      creator.addItem(std::shared_ptr<zim::writer::Item>(new CopyItem(entry.getItem())));
    }
  }

  creator.finishZimCreation();
  return 0;
}
