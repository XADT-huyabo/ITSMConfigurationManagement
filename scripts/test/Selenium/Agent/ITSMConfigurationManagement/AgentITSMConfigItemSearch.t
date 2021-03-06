# --
# Copyright (C) 2001-2017 OTRS AG, http://otrs.com/
# --
# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file COPYING for license information (AGPL). If you
# did not receive this file, see http://www.gnu.org/licenses/agpl.txt.
# --

use strict;
use warnings;
use utf8;

use vars (qw($Self));

# get selenium object
my $Selenium = $Kernel::OM->Get('Kernel::System::UnitTest::Selenium');

$Selenium->RunTest(
    sub {

        my $Helper               = $Kernel::OM->Get('Kernel::System::UnitTest::Helper');
        my $GeneralCatalogObject = $Kernel::OM->Get('Kernel::System::GeneralCatalog');

        # get 'Computer' ConfigItem ID
        my @ConfigItemClassIDs;
        for my $ConfigItemClass (qw(Computer)) {
            my $ConfigItemDataRef = $GeneralCatalogObject->ItemGet(
                Class => 'ITSM::ConfigItem::Class',
                Name  => $ConfigItemClass,
            );
            push @ConfigItemClassIDs, $ConfigItemDataRef->{ItemID};
        }

        # get 'Production' deployment state IDs
        my $ProductionDeplStateDataRef = $GeneralCatalogObject->ItemGet(
            Class => 'ITSM::ConfigItem::DeploymentState',
            Name  => 'Production',
        );
        my $ProductionDeplStateID = $ProductionDeplStateDataRef->{ItemID};

        my $ConfigItemObject = $Kernel::OM->Get('Kernel::System::ITSMConfigItem');
        my $ConfigObject     = $Kernel::OM->Get('Kernel::Config');

        # create ConfigItem numbers
        my @ConfigItemNumbers;
        for my $ConfigNumberCreate ( 1 .. 2 ) {
            my $ConfigItemNumber = $ConfigItemObject->ConfigItemNumberCreate(
                Type    => $ConfigObject->Get('ITSMConfigItem::NumberGenerator'),
                ClassID => $ConfigItemClassIDs[0],
            );
            $Self->True(
                $ConfigItemNumber,
                "ConfigItem number is created - $ConfigItemNumber"
            );
            push @ConfigItemNumbers, $ConfigItemNumber;
        }

        # add the new ConfigItems
        my @ConfigItemIDs;
        for my $ConfigItemCreateNumber (@ConfigItemNumbers) {
            my $ConfigItemID = $ConfigItemObject->ConfigItemAdd(
                Number  => $ConfigItemCreateNumber,
                ClassID => $ConfigItemClassIDs[0],
                UserID  => 1,
            );
            $Self->True(
                $ConfigItemID,
                "ConfigItem is created - ID $ConfigItemID"
            );
            push @ConfigItemIDs, $ConfigItemID;
        }

        # add a new version for each ConfigItem
        my @VersionIDs;
        my $Count    = 1;
        my $RandomID = $Helper->GetRandomID();
        for my $ConfigItemVersion (@ConfigItemIDs) {
            my $VersionID = $ConfigItemObject->VersionAdd(
                Name         => $Count . $RandomID,
                DefinitionID => 1,
                DeplStateID  => $ProductionDeplStateID,
                InciStateID  => 1,
                UserID       => 1,
                ConfigItemID => $ConfigItemVersion,
            );
            $Self->True(
                $VersionID,
                "Version is created - ID $VersionID"
            );
            push @VersionIDs, $VersionID;

            $Count++;
        }

        # create test user and login
        my $TestUserLogin = $Helper->TestUserCreate(
            Groups => [ 'admin', 'users', 'itsm-configitem' ],
        ) || die "Did not get test user";

        $Selenium->Login(
            Type     => 'Agent',
            User     => $TestUserLogin,
            Password => $TestUserLogin,
        );

        # get script alias
        my $ScriptAlias = $ConfigObject->Get('ScriptAlias');

        # navigate to AgentITSMConfigItemSearch
        $Selenium->VerifiedGet("${ScriptAlias}index.pl?Action=AgentITSMConfigItemSearch");

        # wait until form and overlay has loaded, if necessary
        $Selenium->WaitFor( JavaScript => "return typeof(\$) === 'function' && \$('#SearchClassID').length" );

        # check for class select box
        $Self->True(
            $Selenium->find_element( "#SearchClassID", 'css' ),
            "Class select box - found",
        );

        sleep(5);

        # select 'Computer' class
        $Selenium->execute_script(
            "\$('#SearchClassID').val('$ConfigItemClassIDs[0]').trigger('redraw.InputField').trigger('change');"
        );

        # wait until form has loaded, if necessary
        $Selenium->WaitFor( JavaScript => "return typeof(\$) === 'function' && \$('#Attribute').length" );

        # check ConfigItem search page
        for my $ID (
            qw(SearchClassID SearchProfile SearchProfileNew Attribute PreviousVersionSearch ResultForm SearchFormSubmit)
            )
        {

            my $Element = $Selenium->find_element( "#$ID", 'css' );

            $Element->is_enabled();
            $Element->is_displayed();
        }

        # search ConfigItems by test ConfigItem number and names
        $Selenium->execute_script("\$('#Attribute').val('Name').trigger('redraw.InputField').trigger('change');");
        $Selenium->find_element( ".AddButton", 'css' )->click();
        $Selenium->find_element("//input[\@name='Number']")->send_keys('*');
        $Selenium->find_element("//input[\@name='Name']")->send_keys( '*' . $RandomID );
        $Selenium->find_element( "#SearchFormSubmit", 'css' )->VerifiedClick();

        # check for expected result
        for my $CheckConfigItem (@ConfigItemNumbers) {
            $Self->True(
                index( $Selenium->get_page_source(), $CheckConfigItem ) > -1,
                "ConfigItem number $CheckConfigItem - found",
            );
        }

        # verify sorting in table, by default sorting is done by ConfigItemNumber - sort ascending
        # lower ID will on the top of table
        $Self->Is(
            $Selenium->execute_script("return \$('tbody tr:eq(0)').attr('id')"),
            'ConfigItemID_' . $ConfigItemIDs[1],
            "ConfigItemID $ConfigItemIDs[1] is on top of table sort by Number ascending"
        );
        $Self->Is(
            $Selenium->execute_script("return \$('tbody tr:eq(1)').attr('id')"),
            'ConfigItemID_' . $ConfigItemIDs[0],
            "ConfigItemID $ConfigItemIDs[0] is on bottom of table sort by Number ascending"
        );

        # click to sort by Name
        $Selenium->find_element( ".Name", 'css' )->VerifiedClick();

        # check for expected result
        for my $CheckConfigItem (@ConfigItemNumbers) {
            $Self->True(
                index( $Selenium->get_page_source(), $CheckConfigItem ) > -1,
                "ConfigItem number $CheckConfigItem - found",
            );
        }

        # sort is by Name descending
        $Self->Is(
            $Selenium->execute_script("return \$('tbody tr:eq(0)').attr('id')"),
            'ConfigItemID_' . $ConfigItemIDs[0],
            "ConfigItemID $ConfigItemIDs[1] is on top of table sort by Name descending"
        );
        $Self->Is(
            $Selenium->execute_script("return \$('tbody tr:eq(1)').attr('id')"),
            'ConfigItemID_' . $ConfigItemIDs[1],
            "ConfigItemID $ConfigItemIDs[0] is on bottom of table sort by Name descending"
        );

        # click to sort by Name again
        $Selenium->find_element( ".Name", 'css' )->VerifiedClick();

        # verify order is changed, sort by Name ascending
        $Self->Is(
            $Selenium->execute_script("return \$('tbody tr:eq(0)').attr('id')"),
            'ConfigItemID_' . $ConfigItemIDs[1],
            "ConfigItemID $ConfigItemIDs[0] is on top of table sort by Name ascending"
        );
        $Self->Is(
            $Selenium->execute_script("return \$('tbody tr:eq(1)').attr('id')"),
            'ConfigItemID_' . $ConfigItemIDs[0],
            "ConfigItemID $ConfigItemIDs[1] is on bottom of table sort by Name ascending"
        );

        # create ConfigItem numbers
        @ConfigItemNumbers = ();
        for my $ConfigNumberCreate ( 1 .. 35 ) {
            my $ConfigItemNumber = $ConfigItemObject->ConfigItemNumberCreate(
                Type    => $ConfigObject->Get('ITSMConfigItem::NumberGenerator'),
                ClassID => $ConfigItemClassIDs[0],
            );
            $Self->True(
                $ConfigItemNumber,
                "ConfigItem number is created - $ConfigItemNumber"
            );
            push @ConfigItemNumbers, $ConfigItemNumber;
        }

        # add the new ConfigItems
        for my $ConfigItemCreateNumber (@ConfigItemNumbers) {
            my $ConfigItemID = $ConfigItemObject->ConfigItemAdd(
                Number  => $ConfigItemCreateNumber,
                ClassID => $ConfigItemClassIDs[0],
                UserID  => 1,
            );
            $Self->True(
                $ConfigItemID,
                "ConfigItem is created - ID $ConfigItemID"
            );
            push @ConfigItemIDs, $ConfigItemID;
        }

        my @XMLDataArray = [
            undef,
            {
                'Version' => [
                    undef,
                    {

                        'WarrantyExpirationDate' => [
                            undef,
                            {
                                'Content' => '2017-10-10'
                            },
                        ],
                    },
                ],
            },
            {
                'Version' => [
                    undef,
                    {

                        'WarrantyExpirationDate' => [
                            undef,
                            {
                                'Content' => '2017-11-11'
                            },
                        ],
                    },
                ],
            },
        ];

        # add a new version for each ConfigItem
        $Count = 1;
        for my $ConfigItemVersion (@ConfigItemIDs) {

            my $XMLData = ( $Count <= 30 ) ? $XMLDataArray[0] : $XMLDataArray[1];
            my $VersionID = $ConfigItemObject->VersionAdd(
                Name         => $Count . $RandomID,
                DefinitionID => 1,
                DeplStateID  => $ProductionDeplStateID,
                InciStateID  => 1,
                UserID       => 1,
                XMLData      => $XMLData,
                ConfigItemID => $ConfigItemVersion,
            );
            $Self->True(
                $VersionID,
                "Version is created - ID $VersionID"
            );
            push @VersionIDs, $VersionID;

            $Count++;
        }

        # change search option
        $Selenium->find_element( "#ITSMConfigItemSearch", 'css' )->VerifiedClick();

        # wait until form has loaded, if necessary
        $Selenium->WaitFor( JavaScript => "return \$('#Attribute').length" );

        # Add search filter by WarrantyExpirationDate and set date range (8-10-2017 - 15-10-2017).
        $Selenium->execute_script(
            "\$('#Attribute').val('WarrantyExpirationDate').trigger('redraw.InputField').trigger('change');",
        );
        $Selenium->find_element( '.AddButton', 'css' )->click();
        $Selenium->execute_script(
            "\$('#SearchInsert select[id=\"WarrantyExpirationDate::TimeStart::Day\"]').val('8');"
        );
        $Selenium->execute_script(
            "\$('#SearchInsert select[id=\"WarrantyExpirationDate::TimeStart::Month\"]').val('10');"
        );
        $Selenium->execute_script(
            "\$('#SearchInsert select[id=\"WarrantyExpirationDate::TimeStart::Year\"]').val('2017');"
        );
        $Selenium->execute_script(
            "\$('#SearchInsert select[id=\"WarrantyExpirationDate::TimeStop::Day\"]').val('15');"
        );
        $Selenium->execute_script(
            "\$('#SearchInsert select[id=\"WarrantyExpirationDate::TimeStop::Month\"]').val('10');"
        );
        $Selenium->execute_script(
            "\$('#SearchInsert select[id=\"WarrantyExpirationDate::TimeStop::Year\"]').val('2017');"
        );
        $Selenium->find_element("//input[\@name='Number']")->clear();
        $Selenium->find_element("//input[\@name='Number']")->send_keys('*');
        $Selenium->find_element("//input[\@name='Name']")->clear();
        $Selenium->find_element("//input[\@name='Name']")->send_keys( '*' . $RandomID );

        $Selenium->find_element( "#SearchFormSubmit", 'css' )->VerifiedClick();

        $Self->True(
            index( $Selenium->execute_script("return \$('.Pagination').text().trim();"), '1-25 of 30' ) > -1,
            "Check pagination on the first page",
        );

        $Self->Is(
            $Selenium->execute_script("return \$('tbody tr').length;"),
            '25',
            "Check number of config items on the second page",
        );

        # Go to the second page.
        $Selenium->find_element( "#GenericPage2", 'css' )->VerifiedClick();

        $Self->True(
            index( $Selenium->execute_script("return \$('.Pagination').text().trim();"), '26-30 of 30' ) > -1,
            "Check pagination on the second page",
        );

        $Self->Is(
            $Selenium->execute_script("return \$('tbody tr').length;"),
            '5',
            "Check number of config items on the second page",
        );

        # change search option
        $Selenium->find_element( "#ITSMConfigItemSearch", 'css' )->VerifiedClick();

        # wait until form has loaded, if necessary
        $Selenium->WaitFor( JavaScript => "return \$('#Attribute').length" );

        # input wrong search parameters, result should be 'No data found'
        $Selenium->find_element("//input[\@name='Name']")->clear();
        $Selenium->find_element("//input[\@name='Name']")->send_keys('asdfg');
        $Selenium->find_element( "#SearchFormSubmit", 'css' )->VerifiedClick();

        # check for expected result
        $Self->True(
            index( $Selenium->get_page_source(), 'No data found' ) > -1,
            "'No data found' - found",
        );

        # delete created test ConfigItem
        for my $ConfigItemDeleteID (@ConfigItemIDs) {
            my $Success = $ConfigItemObject->ConfigItemDelete(
                ConfigItemID => $ConfigItemDeleteID,
                UserID       => 1,
            );
            $Self->True(
                $Success,
                "ConfigItem is deleted - ID $ConfigItemDeleteID",
            );
        }
    }
);

1;
