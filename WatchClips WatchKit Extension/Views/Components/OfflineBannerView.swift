import SwiftUI

struct OfflineBannerView: View {
    var body: some View {
        ZStack {
            Color(red: 46/255, green: 36/255, blue: 89/255)
                .cornerRadius(8)
            
            VStack(alignment: .center, spacing: 6) {
                HStack(alignment: .center, spacing: 8) {
                    Text("Offline Mode")
                        .font(.headline)
                        .foregroundColor(.white)
                    
                    Image(systemName: "wifi.slash")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(.white)
                }
                .frame(maxWidth: .infinity, alignment: .center)
                
                Text("No internet connection.\nWatch downloaded videos.")
                    .font(.subheadline)
                    .foregroundColor(Color.white.opacity(0.9))
            }
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity)
        }
        .listRowInsets(EdgeInsets(top: 10, leading: 0, bottom: 10, trailing: 0))
        .listRowBackground(Color.clear)
    }
}

struct OfflineBannerView_Previews: PreviewProvider {
    static var previews: some View {
        List {
            OfflineBannerView()
        }
    }
}
