import SwiftUI

struct PosterImage: View {
    let urlString: String
    var width: CGFloat = 108
    var height: CGFloat = 152

    var body: some View {
        Group {
            if let url = URL(string: urlString), urlString.isHTTPURL {
                AsyncImage(url: url, transaction: Transaction(animation: .easeOut(duration: 0.2))) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    default:
                        placeholder
                    }
                }
            } else {
                placeholder
            }
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.white.opacity(0.06), lineWidth: 1)
        )
    }

    private var placeholder: some View {
        ZStack {
            Color.white.opacity(0.06)
            Image(systemName: "film")
                .font(.system(size: 24))
                .foregroundStyle(.white.opacity(0.25))
        }
    }
}

struct VodCard: View {
    let item: VodItem

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack(alignment: .bottomTrailing) {
                PosterImage(urlString: item.pic)
                if !item.remarks.isEmpty {
                    Text(item.remarks)
                        .font(.system(size: 10, weight: .semibold))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Color.black.opacity(0.65), in: RoundedRectangle(cornerRadius: 4))
                        .foregroundStyle(.white)
                        .padding(4)
                }
            }
            Text(item.name)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct SiteRow: View {
    let site: Site

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.orange.opacity(0.18))
                Text(String(site.name.prefix(1)))
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.orange)
            }
            .frame(width: 34, height: 34)

            VStack(alignment: .leading, spacing: 2) {
                Text(site.name)
                    .font(.system(size: 15, weight: .medium))
                if !site.host.isEmpty {
                    Text(site.host)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .padding(.vertical, 2)
    }
}

struct FavoriteCard: View {
    let record: FavoriteRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            PosterImage(urlString: record.item.pic, width: 84, height: 118)
            Text(record.item.name)
                .font(.system(size: 11))
                .foregroundStyle(.white)
                .lineLimit(1)
                .frame(width: 84, alignment: .leading)
        }
    }
}

struct EmptyHint: View {
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "antenna.radiowaves.left.and.right.slash")
                .font(.system(size: 34))
                .foregroundStyle(.secondary)
            Text(title).font(.headline)
            Text(message)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
