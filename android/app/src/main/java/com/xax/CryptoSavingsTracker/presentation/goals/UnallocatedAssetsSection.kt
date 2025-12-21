package com.xax.CryptoSavingsTracker.presentation.goals

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowForward
import androidx.compose.material.icons.filled.Warning
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.xax.CryptoSavingsTracker.presentation.common.AmountFormatters

@Composable
fun UnallocatedAssetsSection(
    items: List<UnallocatedAssetWarning>,
    onAssetClick: (assetId: String) -> Unit,
    modifier: Modifier = Modifier
) {
    if (items.isEmpty()) return

    Card(
        modifier = modifier
            .fillMaxWidth()
            .testTag("unallocatedAssetsSection"),
        colors = CardDefaults.cardColors(
            containerColor = MaterialTheme.colorScheme.tertiaryContainer.copy(alpha = 0.35f)
        )
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                verticalAlignment = Alignment.CenterVertically
            ) {
                Icon(
                    imageVector = Icons.Default.Warning,
                    contentDescription = null,
                    tint = Color(0xFFFF9800)
                )
                Spacer(modifier = Modifier.width(8.dp))
                Text(
                    text = "Unallocated Assets",
                    style = MaterialTheme.typography.titleMedium,
                    color = Color(0xFFFF9800)
                )
                Spacer(modifier = Modifier.weight(1f))
                Text(
                    text = items.size.toString(),
                    style = MaterialTheme.typography.labelMedium,
                    color = Color(0xFFFF9800)
                )
            }

            Text(
                text = "These assets have unallocated portions. Assign them to goals to track progress accurately.",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )

            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                items.forEach { item ->
                    UnallocatedAssetCard(
                        item = item,
                        onClick = { onAssetClick(item.assetId) }
                    )
                }
            }
        }
    }
}

@Composable
private fun UnallocatedAssetCard(
    item: UnallocatedAssetWarning,
    onClick: () -> Unit
) {
    val isCryptoAsset = item.address != null

    Card(
        modifier = Modifier
            .fillMaxWidth()
            .clickable(onClick = onClick)
            .testTag("unallocatedAssetCard_${item.assetId}"),
        colors = CardDefaults.cardColors(
            containerColor = MaterialTheme.colorScheme.surface
        ),
        elevation = CardDefaults.cardElevation(defaultElevation = 1.dp)
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(12.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            Column(modifier = Modifier.weight(1f)) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text(
                        text = item.currency,
                        style = MaterialTheme.typography.titleMedium
                    )
                    Spacer(modifier = Modifier.width(8.dp))
                    Text(
                        text = "• ${item.unallocatedPercentage}% unallocated",
                        style = MaterialTheme.typography.bodySmall,
                        color = Color(0xFFFF9800)
                    )
                }

                if (!item.address.isNullOrBlank()) {
                    Text(
                        text = shortAddress(item.address),
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis
                    )
                }

                Text(
                    text = "${AmountFormatters.formatDisplayAmount(item.unallocatedAmount, isCrypto = isCryptoAsset)} ${item.currency} available",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.primary
                )
            }

            Icon(
                imageVector = Icons.AutoMirrored.Filled.ArrowForward,
                contentDescription = null,
                tint = Color(0xFFFF9800),
                modifier = Modifier.size(20.dp)
            )
        }
    }
}

private fun shortAddress(address: String?): String {
    if (address.isNullOrBlank()) return ""
    return if (address.length > 16) {
        "${address.take(10)}...${address.takeLast(4)}"
    } else {
        address
    }
}
