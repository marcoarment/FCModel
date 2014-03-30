//
//  ViewController.m
//  FCModelTest
//
//  Created by Marco Arment on 9/14/13.
//  Copyright (c) 2013 Marco Arment. All rights reserved.
//

#import "ViewController.h"
#import "PersonCell.h"
#import "Person.h"
#import "Culture.h"

@interface ViewController ()
@property (nonatomic, copy) NSArray *people;
@property (nonatomic, retain) Culture *currentCulture;
@end

@implementation ViewController

- (id)init { return [super initWithNibName:@"ViewController" bundle:nil]; }

- (void)viewDidLoad
{
    [super viewDidLoad];
    UINib *cellNib = [UINib nibWithNibName:@"PersonCell" bundle:nil];
    [self.collectionView registerNib:cellNib forCellWithReuseIdentifier:@"PersonCell"];
    
    [self reloadPeople:nil];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(reloadPeople:) name:FCModelInsertNotification object:Person.class];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(reloadPeople:) name:FCModelDeleteNotification object:Person.class];
}

- (void)reloadPeople:(NSNotification *)notification
{
    if(self.currentCulture == nil)
    {
        self.people = [Person allInstances];
    }
    else
    {
        self.people = [Person instancesWhere:@"cultureCode = ? ORDER BY name" arguments:[NSArray arrayWithObject:self.currentCulture.cultureCode]];
    }
    
    NSLog(@"Reloading with %lu people", (unsigned long) self.people.count);
    [self.collectionView reloadData];
}

- (void)dealloc
{
    [NSNotificationCenter.defaultCenter removeObserver:self name:FCModelInsertNotification object:Person.class];
    [NSNotificationCenter.defaultCenter removeObserver:self name:FCModelDeleteNotification object:Person.class];
}

#pragma mark - UITextFieldDelegate

- (BOOL)textFieldShouldReturn:(UITextField *)textField
{
    [textField resignFirstResponder];
    
    NSError *error = [Person executeUpdateQuery:self.queryField.text];
    if (error) {
        [[[UIAlertView alloc] initWithTitle:@"Query Failed" message:error.localizedDescription delegate:nil cancelButtonTitle:@"Oops" otherButtonTitles:nil] show];
    }
    return NO;
}

#pragma mark - UICollectionViewDataSource

- (NSInteger)numberOfSectionsInCollectionView:(UICollectionView *)collectionView { return 1; }

- (NSInteger)collectionView:(UICollectionView *)collectionView numberOfItemsInSection:(NSInteger)section
{
    return self.people.count;
}

- (UICollectionViewCell *)collectionView:(UICollectionView *)collectionView cellForItemAtIndexPath:(NSIndexPath *)indexPath
{
    PersonCell *cell = [collectionView dequeueReusableCellWithReuseIdentifier:@"PersonCell" forIndexPath:indexPath];
    [cell configureWithPerson:self.people[indexPath.row]];
    return cell;
}

#pragma mark - UICollectionViewDelegate

- (void)collectionView:(UICollectionView *)collectionView didSelectItemAtIndexPath:(NSIndexPath *)indexPath
{
    Person *p = (Person *) self.people[indexPath.row];
    p.taps = p.taps + 1;
    [p save];
    
    [collectionView deselectItemAtIndexPath:indexPath animated:YES];
}

-(IBAction)cultureControlTapped:(id)sender
{
    
    NSLog(@"self.cultureControl.selectedSegmentIndex %li", (long)self.cultureControl.selectedSegmentIndex);
    
    if(self.cultureControl.selectedSegmentIndex == 0)
    {
        self.currentCulture = nil;
        
    }else if(self.cultureControl.selectedSegmentIndex == 1)
    {
        self.currentCulture = [Culture instanceWithPrimaryKey:@"en-AU"];
        
    }else if(self.cultureControl.selectedSegmentIndex == 2)
    {
        self.currentCulture = [Culture instanceWithPrimaryKey:@"en-US"];
        
    }
    
    [self reloadPeople:nil];
}


@end
