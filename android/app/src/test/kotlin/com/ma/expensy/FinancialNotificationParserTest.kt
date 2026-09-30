package com.ma.expensy

import org.junit.Assert.*
import org.junit.Test

class FinancialNotificationParserTest {
    @Test fun diagnosticsAndConfidenceAreConservative() {
        assertEquals("multiple_amounts", FinancialNotificationParser.analyze("Compra aprovada R$ 20,00 e R$ 20,00").reason)
        assertEquals("sensitive", FinancialNotificationParser.analyze("Compra aprovada R$ 20,00 codigo 123456").reason)
        assertEquals("balance_or_invoice", FinancialNotificationParser.analyze("Pagamento de fatura R$ 20,00").reason)
        assertEquals("medium", FinancialNotificationParser.parse("Pagamento realizado R$ 20,00")!!.confidence)
        assertEquals("high", FinancialNotificationParser.parse("Compra de R$ 20,00 aprovada em LOJA")!!.confidence)
        assertNull(FinancialNotificationParser.parse("Pagamento R$ 20,00"))
        assertNull(FinancialNotificationParser.parse("Compra aprovada? Confirme se reconhece R$ 20,00"))
        assertNull(FinancialNotificationParser.parse("Compra aprovada R$ 20,00 não realizada"))
        assertNull(FinancialNotificationParser.parse("Pix recebido e pix enviado R$ 20,00"))
        assertNull(FinancialNotificationParser.parse("Compra aprovada US$ 20,00"))
        assertNull(FinancialNotificationParser.parse("Compra aprovada -R$ 20,00"))
    }
    @Test fun expandedTemplatesAreNotTwoEvents() {
        val result = FinancialNotificationParser.analyzeParts("Compra aprovada R$ 20,00", "Compra aprovada R$ 20,00 em LOJA")
        assertEquals(2000L, result.suggestion!!.cents)
        assertEquals("LOJA", result.suggestion!!.description)
        assertEquals("multiple_amounts", FinancialNotificationParser.analyzeParts("Compra aprovada R$ 20,00", "Outra compra R$ 20,00").reason)
        assertEquals("income", FinancialNotificationParser.parse("Você recebeu um Pix de R$ 120,00")!!.kind)
        assertEquals("expense", FinancialNotificationParser.parse("Você enviou um Pix de R$ 120,00")!!.kind)
    }
    @Test fun recipientAndCardNumbersAreNotRetained() {
        assertEquals("Pix recebido", FinancialNotificationParser.parse("Pix recebido R$ 20,00 de Fulano CPF 12345678900")!!.description)
        assertEquals("Compra / pagamento", FinancialNotificationParser.parse("Compra aprovada R$ 20,00 em LOJA cartao 1234")!!.description)
        assertEquals("unknown", FinancialNotificationParser.parse("Compra no credito R$ 20,00 com debito")!!.medium)
    }
    @Test fun purchaseAndBrazilianMoney() {
        val item = FinancialNotificationParser.parse("Compra aprovada de R$ 1.234,56 em IFOOD")!!
        assertEquals(123456L, item.cents)
        assertEquals("IFOOD", item.description)
        assertEquals("expense", item.kind)
        assertEquals("bank", FinancialNotificationParser.parse("Compra no débito de 32,90 em MERCADO")!!.medium)
        assertEquals("credit", FinancialNotificationParser.parse("Compra no crédito de R$ 32,90 em LOJA")!!.medium)
    }
    @Test fun pixTransferAndRefund() {
        assertEquals("expense", FinancialNotificationParser.parse("Pix enviado de R$ 32,90 para Maria")!!.kind)
        assertEquals("income", FinancialNotificationParser.parse("Pix recebido de R$ 100,50 de João")!!.kind)
        assertEquals("transfer", FinancialNotificationParser.parse("Transferência realizada de R$ 10,00")!!.kind)
        assertEquals("refund", FinancialNotificationParser.parse("Reembolso recebido de R$ 30,00")!!.kind)
        assertEquals("refund", FinancialNotificationParser.parse("Estorno de R$ 30,00")!!.kind)
        assertEquals("expense", FinancialNotificationParser.parse("Pagamento realizado de R$ 30,00")!!.kind)
    }
    @Test fun rejectsUnknownDeniedPromotionalAndAmbiguousAmounts() {
        for (text in listOf("Bom dia!", "Oferta compra aprovada R$ 20,00", "Compra recusada R$ 20,00", "Pix agendado R$ 20,00", "Pagamento de fatura R$ 20,00", "Pix recebido R$ 20,00 saldo R$ 300,00", "Compra aprovada R$ 20,00 e R$ 30,00", "Seu código 123456", "Compra aprovada R$ 1.23,45", "Compra aprovada R$ 0,00")) {
            assertNull(text, FinancialNotificationParser.parse(text))
        }
    }
    @Test fun replayFingerprintIsStableAndDoesNotContainPayload() {
        val item = FinancialNotificationParser.parse("Compra aprovada de R$ 32,90 em IFOOD")!!
        val a = FinancialNotificationParser.fingerprint("com.nu.production", "key", 120000L, item)
        assertEquals(a, FinancialNotificationParser.fingerprint("com.nu.production", "key", 120001L, item))
        assertNotEquals(a, FinancialNotificationParser.fingerprint("com.picpay", "key", 120000L, item))
        assertNotEquals(a, FinancialNotificationParser.fingerprint("com.nu.production", "key2", 120000L, item))
        assertEquals(64, a.length)
        assertFalse(a.contains("IFOOD"))
    }
}
