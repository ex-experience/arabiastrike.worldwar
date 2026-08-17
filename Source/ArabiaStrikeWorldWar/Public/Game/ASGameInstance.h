#pragma once
#include "CoreMinimal.h"
#include "Engine/GameInstance.h"
#include "ASGameInstance.generated.h"
class UASCityDefinition;

UCLASS()
class ARABIASTRIKEWORLDWAR_API UASGameInstance : public UGameInstance
{
    GENERATED_BODY()
public:
    virtual void Init() override;
    UFUNCTION(BlueprintPure) FString GetOnlineBackendMode() const { return OnlineBackendMode; }
    UFUNCTION(BlueprintCallable, Category="World") void SetSelectedCity(UASCityDefinition* City) { SelectedCity = City; }
    UFUNCTION(BlueprintPure, Category="World") UASCityDefinition* GetSelectedCity() const { return SelectedCity; }
private:
    FString OnlineBackendMode = TEXT("Null");
    UPROPERTY() TObjectPtr<UASCityDefinition> SelectedCity;
};
