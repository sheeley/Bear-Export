//
//  ProgressBar.swift
//  BearExport
//
//  Created by Johnny Sheeley on 6/17/20.
//  Copyright © 2020 Johnny Sheeley. All rights reserved.
//

import SwiftUI

struct ProgressBar: View {
    var currentValue: Int
    var total: Int

    var widthPct: CGFloat {
        if total == 0 {
            return 0
        }
        let w = CGFloat(currentValue) / CGFloat(total)
        if w == 0 {
            return 1
        }
        return w
    }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Rectangle().foregroundColor(Color.secondary)
                Rectangle()
                    .frame(width: geo.size.width * self.widthPct) // , height: geo.size.height, alignment: .leading)
                    .foregroundColor(Color.accentColor)
                    .animation(.linear)

                HStack {
                    Spacer()
                    Text("\(self.currentValue) / \(self.total)").padding()
                    Spacer()
                }
            }.cornerRadius(10.0)
        }
    }
}

struct ProgressBar_Previews: PreviewProvider {
    static var previews: some View {
        ProgressBar(currentValue: 25, total: 100)
    }
}
