local Keys = {
	Common = {
		NotAvailable = { key = "Common.NotAvailable", fallback = "N/A" },
		Loading = { key = "Common.Loading", fallback = "Loading..." },
	},
	BodyPart = {
		Stats = {
			Strength = { key = "BodyPart.Stats.Strength", fallback = "Strength: {Value}" },
			Speed = { key = "BodyPart.Stats.Speed", fallback = "Speed: {Value}" },
			Health = { key = "BodyPart.Stats.Health", fallback = "Health: {Value}" },
		},
		Summary = {
			Income = { key = "BodyPart.Summary.Income", fallback = "{IncomePerSecond} Income" },
			Luck = { key = "BodyPart.Summary.Luck", fallback = "x{LuckMultiplier} Luck" },
			RollSpeed = { key = "BodyPart.Summary.RollSpeed", fallback = "x{RollSpeedMultiplier} Roll Speed" },
		},
		Preview = {
			Bundle = { key = "BodyPart.Preview.Bundle", fallback = "Bundle: {BundleName}" },
			Part = { key = "BodyPart.Preview.Part", fallback = "Part: {RegionLabel}" },
			Rarity = { key = "BodyPart.Preview.Rarity", fallback = "Rarity: {RarityName}" },
			Mutation = { key = "BodyPart.Preview.Mutation", fallback = "Mutation: {MutationName}" },
			Size = { key = "BodyPart.Preview.Size", fallback = "Size: {SizeDescriptor} ({SizeMultiplier}x)" },
			CashPerSec = { key = "BodyPart.Preview.CashPerSec", fallback = "Cash Per Sec: {IncomePerSecond}" },
			Chance = { key = "BodyPart.Preview.Chance", fallback = "Chance: {ChanceText}" },
			Existing = { key = "BodyPart.Preview.Existing", fallback = "Existing: {Count}" },
			EverRolled = { key = "BodyPart.Preview.EverRolled", fallback = "{RollNumber} Ever Rolled" },
		},
	},
	Aura = {
		Preview = {
			Bundle = { key = "Aura.Preview.Bundle", fallback = "Aura: {AuraName}" },
			Unlock = { key = "Aura.Preview.Unlock", fallback = "Unlock: {SetName} 6/6" },
			Tier = { key = "Aura.Preview.Tier", fallback = "Tier: {TierName}" },
			LuckBonus = { key = "Aura.Preview.LuckBonus", fallback = "Luck Bonus: {LuckBonus}" },
			RollSpeedBonus = { key = "Aura.Preview.RollSpeedBonus", fallback = "Roll Speed Bonus: {RollSpeedBonus}" },
			MoneyMultiplier = { key = "Aura.Preview.MoneyMultiplier", fallback = "Money Multiplier: x{MoneyMultiplier}" },
			PassiveIncomeBonus = {
				key = "Aura.Preview.PassiveIncomeBonus",
				fallback = "Passive Income Bonus: +{PassiveIncomePerSecond}/s",
			},
		},
	},
	Potion = {
		Preview = {
			Bundle = { key = "Potion.Preview.Bundle", fallback = "Potion: {PotionName}" },
			Duration = { key = "Potion.Preview.Duration", fallback = "Duration: {Duration}" },
			Owned = { key = "Potion.Preview.Owned", fallback = "Owned: x{OwnedAmount}" },
			UseAddTime = { key = "Potion.Preview.UseAddTime", fallback = "Use: Adds another {Duration} to this timer" },
			UseStart = { key = "Potion.Preview.UseStart", fallback = "Use: Starts a {Duration} timer and stacks" },
			ActiveRemaining = { key = "Potion.Preview.ActiveRemaining", fallback = "Active: {Remaining} remaining" },
			ActiveInactive = { key = "Potion.Preview.ActiveInactive", fallback = "Active: Inactive" },
			SellEach = { key = "Potion.Preview.SellEach", fallback = "Sell: {Price} each" },
			BuyEach = { key = "Potion.Preview.BuyEach", fallback = "Buy: {Price} each" },
		},
		Status = {
			Duration = { key = "Potion.Status.Duration", fallback = "Duration: {Duration}" },
			Remaining = { key = "Potion.Status.Remaining", fallback = "Remaining: {Remaining}" },
		},
	},
	Inventory = {
		Capacity = {
			BodyParts = { key = "Inventory.Capacity.BodyParts", fallback = "{CurrentCount}/{MaxCount} Inventory" },
			Auras = { key = "Inventory.Capacity.Auras", fallback = "{CurrentCount}/{MaxCount} Auras" },
			Potions = { key = "Inventory.Capacity.Potions", fallback = "{CurrentCount}/{MaxCount} Potions" },
			Accessories = { key = "Inventory.Capacity.Accessories", fallback = "{CurrentCount}/{MaxCount} Accessories" },
			Materials = { key = "Inventory.Capacity.Materials", fallback = "{CurrentCount} Materials" },
		},
		SellAll = {
			NoneEligible = {
				key = "Inventory.SellAll.NoneEligible",
				fallback = "No unfavorited, unequipped body parts are available to sell.",
			},
			Confirm = {
				key = "Inventory.SellAll.Confirm",
				fallback = "Sell {EligibleCount} unfavorited, unequipped body parts? Favorites and equipped items will stay.",
			},
		},
		SellOne = {
			Confirm = {
				key = "Inventory.SellOne.Confirm",
				fallback = "Sell {BodyPartName}?",
			},
		},
		PotionSell = {
			Title = { key = "Inventory.PotionSell.Title", fallback = "Sell {PotionName}" },
			Owned = { key = "Inventory.PotionSell.Owned", fallback = "Owned: x{OwnedAmount}" },
			Quantity = { key = "Inventory.PotionSell.Quantity", fallback = "Quantity: x{Quantity}" },
			Payout = { key = "Inventory.PotionSell.Payout", fallback = "Payout: ${Payout}" },
		},
		Action = {
			Favorite = { key = "Inventory.Action.Favorite", fallback = "Favorite" },
			Unfavorite = { key = "Inventory.Action.Unfavorite", fallback = "Unfavorite" },
			Working = { key = "Inventory.Action.Working", fallback = "Working..." },
			Use = { key = "Inventory.Action.Use", fallback = "Use" },
			ViewOnly = { key = "Inventory.Action.ViewOnly", fallback = "View Only" },
			Unequip = { key = "Inventory.Action.Unequip", fallback = "Unequip" },
			Equip = { key = "Inventory.Action.Equip", fallback = "Equip" },
		},
	},
	PlayerInspect = {
		Header = {
			Default = { key = "PlayerInspect.Header.Default", fallback = "Player Info" },
		},
		Select = {
			Default = { key = "PlayerInspect.Select.Default", fallback = "Select a body part" },
		},
	},
	Title = {
		CollectionSummary = {
			key = "Title.CollectionSummary",
			fallback = "{OwnedCount}/{TotalCount} Titles Owned",
		},
		EmptyState = {
			SearchNoMatches = {
				key = "Title.EmptyState.SearchNoMatches",
				fallback = "No unlocked titles match your search.",
			},
			FirstUnlock = {
				key = "Title.EmptyState.FirstUnlock",
				fallback = "Keep progressing to unlock your first title.",
			},
		},
		Preview = {
			UnlockBy = {
				key = "Title.Preview.UnlockBy",
				fallback = "{Description}\n\nUnlock by: {HowToGet}",
			},
		},
		Action = {
			EquippedTag = { key = "Title.Action.EquippedTag", fallback = "Equipped" },
			Equip = { key = "Title.Action.Equip", fallback = "Equip" },
			Unequip = { key = "Title.Action.Unequip", fallback = "Unequip" },
		},
		Message = {
			RemoteUnavailable = {
				key = "Title.Message.RemoteUnavailable",
				fallback = "The title equip remote is unavailable right now.",
			},
			UpdateFailed = {
				key = "Title.Message.UpdateFailed",
				fallback = "Failed to update your equipped title.",
			},
		},
	},
	MerchantShop = {
		Common = {
			TimeShards = { key = "MerchantShop.Common.TimeShards", fallback = "{Amount} Time Shards" },
			Cost = { key = "MerchantShop.Common.Cost", fallback = "Cost: {Cost}" },
			StockSummary = {
				key = "MerchantShop.Common.StockSummary",
				fallback = "[Stock: {Stock}/{StockCap}] [Leaves in {DepartureTime}]",
			},
			LeavesIn = { key = "MerchantShop.Common.LeavesIn", fallback = "[Leaves in {DepartureTime}]" },
		},
		Action = {
			Purchase = { key = "MerchantShop.Action.Purchase", fallback = "Purchase" },
			Unavailable = { key = "MerchantShop.Action.Unavailable", fallback = "Unavailable" },
		},
		Message = {
			PurchaseFailedTitle = { key = "MerchantShop.Message.PurchaseFailedTitle", fallback = "Purchase Failed" },
			OutOfStockTitle = { key = "MerchantShop.Message.OutOfStockTitle", fallback = "Out of Stock" },
			OutOfStockBody = {
				key = "MerchantShop.Message.OutOfStockBody",
				fallback = "Nothing else is left before the merchant departs.",
			},
			UnavailableTitle = { key = "MerchantShop.Message.UnavailableTitle", fallback = "Merchant Unavailable" },
			ReturnsIn = { key = "MerchantShop.Message.ReturnsIn", fallback = "The merchant returns in {Countdown}." },
			NotHere = { key = "MerchantShop.Message.NotHere", fallback = "The merchant isn't here right now." },
			NotReady = { key = "MerchantShop.Message.NotReady", fallback = "The merchant is not ready right now." },
			PurchaseUnavailable = {
				key = "MerchantShop.Message.PurchaseUnavailable",
				fallback = "The purchase could not be completed.",
			},
		},
		State = {
			UnavailableName = { key = "MerchantShop.State.UnavailableName", fallback = "Merchant Unavailable" },
			ReturnsSoon = { key = "MerchantShop.State.ReturnsSoon", fallback = "[Returns Soon]" },
			StockEmptyName = { key = "MerchantShop.State.StockEmptyName", fallback = "Merchant Stock Empty" },
			StockEmptyDesc = {
				key = "MerchantShop.State.StockEmptyDesc",
				fallback = "Nothing is left this visit. The merchant leaves in {DepartureTime}.",
			},
		},
	},
	Appraisal = {
		Select = {
			Default = { key = "Appraisal.Select.Default", fallback = "Select a body part" },
			Selected = { key = "Appraisal.Select.Selected", fallback = "Selected: {RegionLabel}" },
		},
		Status = {
			Active = {
				key = "Appraisal.Status.Active",
				fallback = "Appraisal rerolls size and mutation for the selected body part.",
			},
			Inactive = { key = "Appraisal.Status.Inactive", fallback = "Appraisal is unavailable right now." },
		},
		Fields = {
			Cost = { key = "Appraisal.Fields.Cost", fallback = "Cost: {Cost}$" },
			Worth = { key = "Appraisal.Fields.Worth", fallback = "Worth: ${Worth}" },
			WorthEmpty = { key = "Appraisal.Fields.WorthEmpty", fallback = "Worth:" },
			Action = { key = "Appraisal.Fields.Action", fallback = "Appraise" },
		},
		Message = {
			InsufficientFunds = {
				key = "Appraisal.Message.InsufficientFunds",
				fallback = "You don't have enough money to appraise this body part.",
			},
			NotReady = { key = "Appraisal.Message.NotReady", fallback = "The appraiser is not ready right now." },
			Unavailable = { key = "Appraisal.Message.Unavailable", fallback = "The appraiser is unavailable right now." },
			SelectFirst = { key = "Appraisal.Message.SelectFirst", fallback = "Select an equipped body part first." },
			Success = {
				key = "Appraisal.Message.Success",
				fallback = "You have appraised your item.<br/><br/><b>Mutation:</b> {BeforeMutation} -> {AfterMutation}<br/><b>Size:</b> {BeforeSize} ({BeforeScale}x) -> {AfterSize} ({AfterScale}x)",
			},
		},
		Risk = {
			Mutation = { key = "Appraisal.Risk.Mutation", fallback = "{MutationName} mutation" },
			Size = { key = "Appraisal.Risk.Size", fallback = "{SizeDescriptor} size ({SizeMultiplier}x)" },
			JoinTwo = { key = "Appraisal.Risk.JoinTwo", fallback = "{FirstRisk} and {SecondRisk}" },
			Continue = {
				key = "Appraisal.Risk.Continue",
				fallback = "This appraisal may reroll your current {RiskText} into something worse. Continue?",
			},
		},
	},
	Marketplace = {
		Gift = {
			DefaultName = { key = "Marketplace.Gift.DefaultName", fallback = "Gift" },
			ChooseRecipient = {
				key = "Marketplace.Gift.ChooseRecipient",
				fallback = "Choose player to receive gift: {DisplayName}",
			},
			NoRecipients = {
				key = "Marketplace.Gift.NoRecipients",
				fallback = "No other players available to receive gift: {DisplayName}",
			},
		},
		Price = {
			Owned = { key = "Marketplace.Price.Owned", fallback = "Owned" },
		},
	},
}

return table.freeze(Keys)
