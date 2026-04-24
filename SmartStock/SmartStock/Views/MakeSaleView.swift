//
//  MakeSaleView.swift
//  SmartStock
//
//  Created by Nishan Narain on 4/15/26.
//

import SwiftUI
import Supabase



struct MakeSaleView: View {
    @EnvironmentObject var sessionManager: SessionManager

    @State private var searchText = ""
    @State private var products: [Product] = []
    @State private var cart: [CartItem] = []
    @State private var discountText = ""
    @State private var isCheckingOut = false
    @State private var checkoutMessage: String?
    @State private var checkoutError: String?
    @State private var isShowingScanner = false
    @State private var scannedBarcode = ""
    @State private var scannerError: String?
    @State private var editingPriceItemID: UUID?
    @State private var editedUnitPriceText = ""
    @State private var editingDiscountItemID: UUID?
    @State private var editedItemDiscountText = ""
    @FocusState private var isSearchFieldFocused: Bool
    @State private var searchTask: Task<Void, Never>?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {

                // 🔍 Search Bar + Overlay Results
                ZStack(alignment: .top) {
                    VStack(spacing: 0) {
                        HStack(spacing: 10) {
                            TextField("Search product...", text: $searchText)
                                .textFieldStyle(.roundedBorder)
                                .focused($isSearchFieldFocused)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled(true)
                                .submitLabel(.search)
                                .onAppear {
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                        isSearchFieldFocused = true
                                    }
                                }
                                .onChange(of: searchText) {
                                    scheduleSearch()
                                }

                            Button {
                                checkoutError = nil
                                checkoutMessage = nil
                                scannerError = nil
                                isShowingScanner = true
                            } label: {
                                Image(systemName: "barcode.viewfinder")
                                    .font(.title2)
                                    .frame(width: 44, height: 44)
                            }
                            .buttonStyle(.bordered)
                        }

                        if let scannerError {
                            Text(scannerError)
                                .font(.caption)
                                .foregroundColor(.red)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.top, 6)
                        }
                    }

                    if isShowingSearchResults {
                        ScrollView {
                            VStack(spacing: 0) {
                                ForEach(products) { product in
                                    Button {
                                        addToCart(product)
                                    } label: {
                                        HStack(alignment: .top, spacing: 12) {
                                            VStack(alignment: .leading, spacing: 4) {
                                                Text(product.name)
                                                    .font(.headline)
                                                    .foregroundColor(.primary)
                                                    .lineLimit(1)

                                                if let price = product.price {
                                                    Text("Price: $\(price, specifier: "%.2f")")
                                                        .font(.subheadline)
                                                        .foregroundColor(.secondary)
                                                }

                                                if let sku = product.sku, !sku.isEmpty {
                                                    Text("SKU: \(sku)")
                                                        .font(.caption)
                                                        .foregroundColor(.secondary)
                                                        .lineLimit(1)
                                                }
                                            }
                                            .frame(maxWidth: .infinity, alignment: .leading)

                                            Image(systemName: "plus.circle.fill")
                                                .font(.title3)
                                                .foregroundColor(.accentColor)
                                                .padding(.top, 2)
                                        }
                                        .padding(.horizontal)
                                        .padding(.vertical, 12)
                                        .frame(maxWidth: .infinity, minHeight: 72, alignment: .topLeading)
                                        .background(Color(.systemBackground))
                                        .contentShape(Rectangle())
                                    }

                                    if product.id != products.last?.id {
                                        Divider()
                                            .padding(.leading)
                                    }
                                }
                            }
                        }
                        .frame(maxHeight: 260)
                        .background(Color(.systemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color(.systemGray4), lineWidth: 1)
                        )
                        .offset(y: scannerError == nil ? 50 : 72)
                        .shadow(radius: 4)
                    }
                }
                .sheet(isPresented: $isShowingScanner) {
                    BarcodeScannerSheet(
                        scannedCode: $scannedBarcode,
                        isPresented: $isShowingScanner,
                        onScanned: { code in
                            Task {
                                await handleScannedBarcode(code)
                            }
                        }
                    )
                }
                .padding([.horizontal, .top])
                .frame(height: scannerError == nil ? 100 : 124)
                .zIndex(1)

                VStack(spacing: 0) {
                    if cart.isEmpty {
                        Spacer()

                        VStack(spacing: 10) {
                            Image(systemName: "cart")
                                .font(.system(size: 44))
                                .foregroundColor(.secondary)

                            Text("Cart is empty")
                                .font(.headline)

                            Text("Search for a product to add it to the sale.")
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .padding()

                        Spacer()
                    } else {
                        List {
                            ForEach(cart) { item in
                                HStack(spacing: 16) {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(item.product.name)
                                            .font(.headline)

                                        Text("$\(item.unitPrice, specifier: "%.2f") each")
                                            .font(.subheadline)
                                            .foregroundColor(.secondary)

                                        if item.discountAmount > 0 {
                                            Text("Item discount: -$\(item.discountAmount, specifier: "%.2f")")
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                        }
                                    }

                                    Spacer()

                                    HStack(spacing: 8) {
                                        Button {
                                            decreaseQuantity(for: item)
                                        } label: {
                                            Image(systemName: "minus.circle.fill")
                                                .font(.title3)
                                        }
                                        .buttonStyle(.plain)

                                        Text("\(item.quantity)")
                                            .frame(minWidth: 24)

                                        Button {
                                            increaseQuantity(for: item)
                                        } label: {
                                            Image(systemName: "plus.circle.fill")
                                                .font(.title3)
                                        }
                                        .buttonStyle(.plain)
                                    }

                                    Text("$\(item.lineTotal, specifier: "%.2f")")
                                        .font(.headline)
                                        .frame(minWidth: 70, alignment: .trailing)
                                }
                                .padding(.vertical, 2)
                                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                    if canApplySaleDiscount {
                                        Button("Discount") {
                                            editingDiscountItemID = item.id
                                            editedItemDiscountText = String(format: "%.2f", item.discountAmount)
                                        }
                                        .tint(.orange)
                                    }

                                    if canChangeSaleItemPrice {
                                        Button("Price") {
                                            editingPriceItemID = item.id
                                            editedUnitPriceText = String(format: "%.2f", item.unitPrice)
                                        }
                                        .tint(.blue)
                                    }
                                }
                            }
                            .onDelete(perform: removeFromCart)
                        }
                        .listStyle(.plain)
                        .listRowSpacing(6)
                        .contentMargins(.top, 12, for: .scrollContent)
                    }

                    Divider()

                    VStack {
                        if canApplySaleDiscount {
                            TextField("Discount", text: $discountText)
                                .keyboardType(.decimalPad)
                                .textFieldStyle(.roundedBorder)
                        }

                        Text("Subtotal: $\(subtotal, specifier: "%.2f")")
                            .font(.subheadline)

                        if canApplySaleDiscount, discountAmount > 0 {
                            Text("Discount: -$\(discountAmount, specifier: "%.2f")")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }

                        Text("Total: $\(total, specifier: "%.2f")")
                            .font(.headline)

                        if let checkoutError {
                            Text(checkoutError)
                                .foregroundColor(.red)
                                .font(.subheadline)
                                .multilineTextAlignment(.center)
                        }

                        if let checkoutMessage {
                            Text(checkoutMessage)
                                .foregroundColor(.green)
                                .font(.subheadline)
                                .multilineTextAlignment(.center)
                        }

                        Button("Clear Cart") {
                            clearCart()
                        }
                        .foregroundColor(.red)
                        .disabled(cart.isEmpty || isCheckingOut)

                        Button {
                            Task {
                                await checkout()
                            }
                        } label: {
                            if isCheckingOut {
                                ProgressView()
                                    .frame(maxWidth: .infinity)
                            } else {
                                Text("Checkout")
                                    .frame(maxWidth: .infinity)
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(cart.isEmpty || isCheckingOut)
                    }
                    .padding()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .navigationTitle("Make Sale")
            .navigationBarTitleDisplayMode(.inline)
            .alert("Change Item Price", isPresented: isEditingItemPrice) {
                TextField("Unit price", text: $editedUnitPriceText)
                    .keyboardType(.decimalPad)
                Button("Cancel", role: .cancel) {
                    editingPriceItemID = nil
                }
                Button("Save") {
                    applyEditedPrice()
                }
            } message: {
                Text("Update the unit price for this cart item.")
            }
            .alert("Item Discount", isPresented: isEditingItemDiscount) {
                TextField("Discount amount", text: $editedItemDiscountText)
                    .keyboardType(.decimalPad)
                Button("Cancel", role: .cancel) {
                    editingDiscountItemID = nil
                }
                Button("Save") {
                    applyEditedItemDiscount()
                }
            } message: {
                Text("Apply a discount to this cart line.")
            }
            .onDisappear {
                searchTask?.cancel()
            }
        }
    }

    var canApplySaleDiscount: Bool {
        sessionManager.currentUser?.canAccess(.applySaleDiscount) == true
    }

    var canChangeSaleItemPrice: Bool {
        sessionManager.currentUser?.canAccess(.changeSaleItemPrice) == true
    }

    var subtotal: Double {
        cart.reduce(0) { $0 + $1.subtotal }
    }

    var discountedCartSubtotal: Double {
        cart.reduce(0) { $0 + $1.lineTotal }
    }

    var total: Double {
        max(discountedCartSubtotal - discountAmount, 0)
    }

    var discountAmount: Double {
        guard canApplySaleDiscount else { return 0 }
        let trimmed = discountText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let value = Double(trimmed), value > 0 else { return 0 }
        return min(value, discountedCartSubtotal)
    }

    var isEditingItemPrice: Binding<Bool> {
        Binding {
            editingPriceItemID != nil
        } set: { isPresented in
            if !isPresented {
                editingPriceItemID = nil
            }
        }
    }

    var isEditingItemDiscount: Binding<Bool> {
        Binding {
            editingDiscountItemID != nil
        } set: { isPresented in
            if !isPresented {
                editingDiscountItemID = nil
            }
        }
    }

    var isShowingSearchResults: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !products.isEmpty
    }

    func addToCart(_ product: Product) {
        checkoutError = nil
        checkoutMessage = nil
        searchText = ""
        products = []
        scannedBarcode = ""
        scannerError = nil
        isSearchFieldFocused = true
        if let index = cart.firstIndex(where: { $0.product.id == product.id }) {
            cart[index].quantity += 1
        } else {
            cart.append(CartItem(product: product, quantity: 1))
        }
    }

    func increaseQuantity(for item: CartItem) {
        checkoutError = nil
        checkoutMessage = nil

        guard let index = cart.firstIndex(where: { $0.id == item.id }) else { return }
        cart[index].quantity += 1
        cart[index].discountAmount = min(cart[index].discountAmount, cart[index].subtotal)
    }

    func decreaseQuantity(for item: CartItem) {
        checkoutError = nil
        checkoutMessage = nil

        guard let index = cart.firstIndex(where: { $0.id == item.id }) else { return }

        if cart[index].quantity > 1 {
            cart[index].quantity -= 1
            cart[index].discountAmount = min(cart[index].discountAmount, cart[index].subtotal)
        } else {
            cart.remove(at: index)
        }
    }

    func removeFromCart(at offsets: IndexSet) {
        checkoutError = nil
        checkoutMessage = nil
        cart.remove(atOffsets: offsets)
    }

    func clearCart() {
        checkoutError = nil
        checkoutMessage = nil
        scannerError = nil
        products = []
        cart.removeAll()
        discountText = ""
        isSearchFieldFocused = true
    }
    func handleScannedBarcode(_ code: String) async {
        let trimmedCode = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedCode.isEmpty else { return }

        await MainActor.run {
            scannedBarcode = trimmedCode
            searchText = trimmedCode
            products = []
            checkoutError = nil
            checkoutMessage = nil
            scannerError = nil
        }

        await searchProductByBarcode(trimmedCode)
    }

    func searchProductByBarcode(_ barcode: String) async {
        do {
            // 1️⃣ Try direct match in products table
            let directResults: [Product] = try await supabase
                .from("products")
                .select("product_id, name, sku, price")
                .or("barcode.eq.\(barcode),sku.eq.\(barcode)")
                .limit(1)
                .execute()
                .value

            if let product = directResults.first {
                await MainActor.run {
                    addToCart(product)
                }
                return
            }

            // 2️⃣ Try lookup in product_barcodes table
            struct BarcodeMatch: Decodable {
                let product_id: Int
            }

            let barcodeResults: [BarcodeMatch] = try await supabase
                .from("product_barcodes")
                .select("product_id")
                .eq("barcode", value: barcode)
                .limit(1)
                .execute()
                .value

            guard let match = barcodeResults.first else {
                await MainActor.run {
                    scannerError = "No product found for barcode: \(barcode)"
                    isSearchFieldFocused = true
                }
                return
            }

            // 3️⃣ Fetch actual product using product_id
            let products: [Product] = try await supabase
                .from("products")
                .select("product_id, name, sku, price")
                .eq("product_id", value: match.product_id)
                .limit(1)
                .execute()
                .value

            await MainActor.run {
                if let product = products.first {
                    addToCart(product)
                } else {
                    scannerError = "Product exists but could not be loaded."
                }
            }

        } catch {
            await MainActor.run {
                scannerError = "Unable to scan product right now."
                isSearchFieldFocused = true
            }
            print("BARCODE SEARCH ERROR:", error)
        }
    }

    func searchProducts() async {
        let trimmedSearch = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        checkoutError = nil
        guard !trimmedSearch.isEmpty else {
            products = []
            return
        }

        do {
            let results: [Product] = try await supabase
                .from("products")
                .select("product_id, name, sku, price")
                .or("name.ilike.%\(trimmedSearch)%,sku.ilike.%\(trimmedSearch)%,barcode.ilike.%\(trimmedSearch)%")
                .limit(4)
                .execute()
                .value

            if Task.isCancelled { return }

            if !results.isEmpty {
                await MainActor.run {
                    products = results
                }
                return
            }

            struct BarcodeMatch: Decodable {
                let product_id: Int
            }

            let barcodeResults: [BarcodeMatch] = try await supabase
                .from("product_barcodes")
                .select("product_id")
                .eq("barcode", value: trimmedSearch)
                .limit(1)
                .execute()
                .value

            guard let match = barcodeResults.first else {
                await MainActor.run {
                    products = []
                }
                return
            }

            let matchedProducts: [Product] = try await supabase
                .from("products")
                .select("product_id, name, sku, price")
                .eq("product_id", value: match.product_id)
                .limit(1)
                .execute()
                .value

            if Task.isCancelled { return }

            await MainActor.run {
                products = matchedProducts
            }
        } catch {
            if Task.isCancelled { return }
            print("SEARCH ERROR:", error)
        }
    }

    func scheduleSearch() {
        searchTask?.cancel()

        let trimmedSearch = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedSearch.isEmpty else {
            products = []
            return
        }

        searchTask = Task {
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled else { return }
            await searchProducts()
        }
    }

    func checkout() async {
        guard let user = sessionManager.currentUser,
              let store = sessionManager.selectedStore,
              !cart.isEmpty else { return }

        isCheckingOut = true
        checkoutError = nil
        checkoutMessage = nil
        defer { isCheckingOut = false }

        do {
            try await CheckoutService.checkout(
                cart: cart,
                discountAmount: discountAmount,
                user: user,
                store: store
            )

            cart.removeAll()
            products = []
            searchText = ""
            scannedBarcode = ""
            scannerError = nil
            discountText = ""
            isSearchFieldFocused = true
            checkoutMessage = "Sale completed successfully."
        } catch {
            checkoutError = error.localizedDescription
            print("CHECKOUT ERROR:", error)
        }
    }

    func applyEditedPrice() {
        guard let editingPriceItemID,
              let index = cart.firstIndex(where: { $0.id == editingPriceItemID }) else {
            self.editingPriceItemID = nil
            return
        }

        guard let newPrice = Double(editedUnitPriceText.trimmingCharacters(in: .whitespacesAndNewlines)),
              newPrice >= 0 else {
            checkoutError = "Enter a valid unit price."
            return
        }

        cart[index].unitPrice = newPrice
        cart[index].discountAmount = min(cart[index].discountAmount, cart[index].subtotal)
        self.editingPriceItemID = nil
    }

    func applyEditedItemDiscount() {
        guard let editingDiscountItemID,
              let index = cart.firstIndex(where: { $0.id == editingDiscountItemID }) else {
            self.editingDiscountItemID = nil
            return
        }

        guard let newDiscount = Double(editedItemDiscountText.trimmingCharacters(in: .whitespacesAndNewlines)),
              newDiscount >= 0 else {
            checkoutError = "Enter a valid item discount."
            return
        }

        cart[index].discountAmount = min(newDiscount, cart[index].subtotal)
        self.editingDiscountItemID = nil
    }
}
