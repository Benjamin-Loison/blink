//////////////////////////////////////////////////////////////////////////////////
//
// B L I N K
//
// Copyright (C) 2016-2019 Blink Mobile Shell Project
//
// This file is part of Blink.
//
// Blink is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// Blink is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with Blink. If not, see <http://www.gnu.org/licenses/>.
//
// In addition, Blink is also subject to certain additional terms under
// GNU GPL version 3 section 7.
//
// You should have received a copy of these additional terms immediately
// following the terms and conditions of the GNU General Public License
// which accompanied the Blink Source Code. If not, see
// <http://www.github.com/blinksh/blink>.
//
////////////////////////////////////////////////////////////////////////////////

import SwiftUI

fileprivate struct HostCard: Equatable {
  let host: BKHosts
  let alias: String
  let hostName: String
  let conflicted: Bool
  
  init(host: BKHosts) {
    self.host = host
    self.alias = host.host
    self.hostName = host.hostName
    
    if let num = host.iCloudConflictDetected,
      num.boolValue == true,
      let _ = host.iCloudConflictCopy {
      self.conflicted = true
    } else {
      BKHosts.markHost(host.host, for: BKHosts.record(fromHost: host), withConflict: false)
      self.conflicted = false
    }
  }
}

struct HostRow: View {
  fileprivate let card: HostCard
  
  var reloadList: () -> ()
  
  var body: some View {
    Row(
      content: {
        HStack {
          Text(card.alias)
          Spacer()
          Text(card.hostName)
            .font(.system(.subheadline)).foregroundColor(.secondary)
          if card.conflicted {
            Image(systemName: "exclamationmark.icloud.fill")
              .foregroundColor(.red)
          }
        }
      },
      details: {
        HostView(host: card.host, reloadList: reloadList)
      }
    )
  }
}

struct SortButton<T>: View where T: Equatable {
  let label: String
  @Binding var sortType: T
  let asc, desc: T
  
  var body: some View {
    Button {
      self.sortType = self.sortType == asc ? desc : asc
    } label: {
      HStack {
        Text(label)
        Spacer()
        if self.sortType == asc {
          Image(systemName: "chevron.up")
        } else if self.sortType == desc {
          Image(systemName: "chevron.down")
        }
      }
    }
  }
}

struct HostListView: View {
  @StateObject private var _state = HostsObservable()
  @EnvironmentObject private var _nav: Nav
  
  var body: some View {
    Group {
      if _state.list.isEmpty {
        Button(
          action: _addHost,
          label: { Label("Add new host", systemImage: "plus") }
        )
      } else {
        List {
          ForEach(_state.list, id: \.alias) {
            HostRow(card: $0, reloadList: _state.reloadHosts)
          }.onDelete(perform: _state.deleteHosts)
        }
        .listStyle(InsetGroupedListStyle())
        .navigationBarItems(
          trailing: HStack {
            Menu {
              Section(header: Text("Order")) {
                SortButton(label: "Alias",    sortType: $_state.sortType, asc: .aliasAsc, desc: .aliasDesc)
                SortButton(label: "HostName", sortType: $_state.sortType, asc: .hostNameAsc, desc: .hostNameDesc)
              }
            } label: { Image(systemName: "list.bullet").frame(width: 38, height: 38, alignment: .center) }
            Button(
              action: _addHost,
              label: { Image(systemName: "plus").frame(width: 38, height: 38, alignment: .center) }
            )
          }
        )
      }
    }
    .onAppear(perform: _state.startSync)
    .navigationBarTitle("Hosts")
  }
  
  private func _addHost() {
    let rootView = HostView(host: nil, reloadList: _state.reloadHosts).environmentObject(_nav)
    let vc = UIHostingController(rootView: rootView)
    _nav.navController.pushViewController(vc, animated: true)
  }
}


fileprivate class HostsObservable: ObservableObject {
  enum HostSortType {
    case aliasAsc, aliasDesc, hostNameAsc, hostNameDesc
    
    var sortFn: (_ a: HostCard, _ b: HostCard) -> Bool {
      switch self {
      case .aliasAsc:     return { a, b in a.alias < b.alias }
      case .aliasDesc:    return { a, b in b.alias < a.alias }
      case .hostNameAsc:  return { a, b in a.hostName < b.hostName }
      case .hostNameDesc: return { a, b in b.hostName < a.hostName }
      }
    }
  }
  
  @Published var sortType: HostSortType = .aliasAsc {
    didSet {
      list = list.sorted(by: sortType.sortFn)
    }
  }
  
  @Published var list: [HostCard] = BKHosts.allHosts()
    .map(HostCard.init(host:))
    .sorted(by: HostSortType.aliasAsc.sortFn)
  
  var _syncStarted = false
  
  func startSync() {
    if _syncStarted {
      return
    }
    if let syncHandler = BKiCloudSyncHandler.shared() {
      _syncStarted = true
      syncHandler.mergeHostCompletionBlock = {
        DispatchQueue.main.async {
          self.reloadHosts()
        }
      }
      syncHandler.check(forReachabilityAndSync: nil)
    }
  }
  
  func reloadHosts() {
    self.list = BKHosts.allHosts()
      .map(HostCard.init(host:))
      .sorted(by: sortType.sortFn)
  }
  
  func deleteHosts(indexSet: IndexSet) {
    let hostsToDelete = indexSet.map { list[$0] }
    
    let syncHandler = BKiCloudSyncHandler.shared()
    let allHosts = BKHosts.all()
    for h in hostsToDelete {
      if let recordId = h.host.iCloudRecordId {
        syncHandler?.deleteRecord(recordId, of: BKiCloudRecordTypeHosts)
      }
      
      allHosts?.remove(h.host)
    }
    BKHosts.save()
    list.remove(atOffsets: indexSet)
  }
}


